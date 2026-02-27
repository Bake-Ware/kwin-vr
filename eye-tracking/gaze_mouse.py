#!/home/alarm/gaze-venv/bin/python3
"""
gaze_mouse.py — IR eye camera → mouse control (EyeTrackVR RANSAC + pye3d)

Pipeline (same as EyeTrackVR):
  1. RANSAC ellipse fit on largest dark contour  (ransac.py algorithm)
  2. pye3d 3D eye model  — learns eye globe position over ~100 frames,
     then outputs geometrically-correct theta/phi gaze angles
  3. Warmup: accumulate 150 frames while user looks around → learn neutral
  4. Map (theta, phi) delta from neutral → screen pixels
  5. Inject mouse via evdev (Wayland-safe)

pye3d builds a better and better 3D model the longer you run it.
No screen-target calibration required.

Install deps:  pip install opencv-python evdev numpy onnxruntime pye3d
Permissions:   sudo usermod -aG input $USER   (then re-login)
Usage:         python3 gaze_mouse.py [camera_index]

Controls:
  W      — redo warmup (re-learn neutral gaze position)
  A      — save current calibration to disk
  P      — pause / resume mouse
  F      — flip X axis (restart warmup)
  V      — flip Y axis (restart warmup)
  +/-    — threshold sensitivity (more/less dark area detected)
  [/]    — sensitivity: scale gaze range up/down
  Q/ESC  — quit
"""

import sys, time, math, argparse
from pathlib import Path
import numpy as np
import cv2
from collections import deque

try:
    from evdev import UInput, ecodes as e
    EVDEV_OK = True
except ImportError:
    print("WARNING: evdev not installed. Mouse injection disabled.")
    EVDEV_OK = False

from pye3d.camera import CameraModel
from pye3d.detector_3d import Detector3D, DetectorMode

# ══════════════════════════════════════════════════════════════════════════════
#  CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

CAMERA_INDEX = 0
CAMERA_W     = 320
CAMERA_H     = 240
CAMERA_FPS   = 120

# Focal length in pixels (camera intrinsic).
# Rule of thumb: CAMERA_W / (2 * tan(half_FOV)).
#   90° FOV → ~160    60° FOV → ~277    120° FOV → ~92
CAMERA_FX    = 150.0

SCREEN_W     = 1920
SCREEN_H     = 1080

# RANSAC threshold: min_pixel_value + THRESH_ADD defines which pixels are "dark".
# Lower = more pixels captured (works better with weak IR).
# Higher = stricter (less noise, needs good IR contrast).
# Press +/- to tune live.
THRESH_ADD   = 11

# Warmup frames before tracking starts (user looks around naturally).
WARMUP_FRAMES = 200

# Gaze range assumed for uncalibrated fallback (degrees, half-range each side).
GAZE_RANGE_H = 25.0
GAZE_RANGE_V = 20.0

# Kalman smoothing. Higher = smoother/laggier.
KALMAN_PROCESS_NOISE = 1.0
KALMAN_MEAS_NOISE    = 150.0

FLIP_X = True
FLIP_Y = False

DWELL_SECONDS = 0
DWELL_RADIUS  = 60

SHOW_PREVIEW  = True
PREVIEW_SCALE = 2.0

CAL_FILE = Path.home() / ".config" / "gaze_mouse_pye3d.npz"

# ══════════════════════════════════════════════════════════════════════════════


# ── Virtual mouse ──────────────────────────────────────────────────────────────

def create_uinput_mouse():
    if not EVDEV_OK:
        return None
    try:
        return UInput(
            {e.EV_REL: [e.REL_X, e.REL_Y],
             e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE]},
            name="gaze-mouse", version=0x1)
    except PermissionError:
        print("ERROR: Cannot open /dev/uinput. Run: sudo usermod -aG input $USER")
        return None

def mouse_move(ui, dx, dy):
    if ui is None or (dx == 0 and dy == 0): return
    if dx: ui.write(e.EV_REL, e.REL_X, int(dx))
    if dy: ui.write(e.EV_REL, e.REL_Y, int(dy))
    ui.syn()

def mouse_click(ui):
    if ui is None: return
    ui.write(e.EV_KEY, e.BTN_LEFT, 1); ui.syn()
    time.sleep(0.05)
    ui.write(e.EV_KEY, e.BTN_LEFT, 0); ui.syn()


# ── RANSAC ellipse fitting (EyeTrackVR algorithm) ─────────────────────────────

def _fit_rotated_ellipse_ransac(data, rng, iter=45, sample_num=10, offset=80):
    """RANSAC-based ellipse fit on contour point cloud. From EyeTrackVR/ransac.py."""
    len_data = len(data)
    if len_data < sample_num:
        return None

    ret_dtype = np.float64
    rng_sample = rng.random((iter, len_data)).argsort()[:, :sample_num]

    datamod = np.concatenate([
        data,
        data**2,
        (data[:, 0] * data[:, 1])[:, np.newaxis],
        np.ones((len_data, 1), dtype=ret_dtype),
        (-1 * data[:, 0]**2)[:, np.newaxis],
    ], axis=1, dtype=ret_dtype)

    datamod_slim        = np.array(datamod[:, :5], dtype=ret_dtype)
    datamod_rng         = datamod[rng_sample]
    datamod_rng6        = datamod_rng[:, :, 6]
    datamod_rng_swap    = datamod_rng[:, :, [4, 3, 0, 1, 5]]
    datamod_rng_swap_T  = datamod_rng_swap.transpose((0, 2, 1))
    datamod_rng_5x5     = np.matmul(datamod_rng_swap_T, datamod_rng_swap)
    datamod_rng_p5smp   = np.matmul(np.linalg.inv(datamod_rng_5x5), datamod_rng_swap_T)
    datamod_rng_p       = np.matmul(datamod_rng_p5smp,
                                    datamod_rng6[:, :, np.newaxis]).reshape((-1, 5))

    ellipse_y_arr = np.asarray([
        datamod_rng_p[:, 2], datamod_rng_p[:, 3],
        np.ones(len(datamod_rng_p)),
        datamod_rng_p[:, 1], datamod_rng_p[:, 0],
    ], dtype=ret_dtype)

    ellipse_data_arr   = (datamod_slim @ ellipse_y_arr
                          + np.asarray(datamod_rng_p[:, 4])).T
    ellipse_data_index = np.argmax(
        np.sum(np.abs(ellipse_data_arr) < offset, axis=1))
    effective_data_arr = ellipse_data_arr[ellipse_data_index]
    effective_p        = datamod_rng_p[ellipse_data_index]

    return _fit_rotated_ellipse(effective_data_arr, effective_p)


def _fit_rotated_ellipse(data, P):
    """Recover ellipse parameters from RANSAC coefficients."""
    a, b, c, d, ef, f = 1.0, P[0], P[1], P[2], P[3], P[4]
    theta     = 0.5 * np.arctan(b / (a - c), dtype=np.float64)
    theta_sin = np.sin(theta, dtype=np.float64)
    theta_cos = np.cos(theta, dtype=np.float64)
    cxy       = b**2 - 4*a*c
    cx        = (2*c*d - b*ef) / cxy
    cy        = (2*a*ef - b*d) / cxy
    cu        = a*cx**2 + b*cx*cy + c*cy**2 - f
    cu_r      = np.array([
        a*theta_cos**2 + b*theta_cos*theta_sin + c*theta_sin**2,
        a*theta_sin**2 - b*theta_cos*theta_sin + c*theta_cos**2,
    ])
    if cu <= 1:
        return None
    wh = np.sqrt(cu / cu_r)
    return cx, cy, wh[0], wh[1], theta


_rng = np.random.default_rng()

def detect_pupil_ransac(gray, thresh_add, frame_for_draw=None):
    """
    Detect pupil using RANSAC ellipse fit on the largest dark contour.
    Returns (cx, cy, w, h, theta_rad) in image pixels, or None.
    """
    blurred = cv2.GaussianBlur(gray, (9, 9), 10)
    h, w    = gray.shape

    min_val, _, _, _ = cv2.minMaxLoc(blurred)
    threshold_val    = min_val + thresh_add
    _, thresh_img    = cv2.threshold(blurred, threshold_val, 255, cv2.THRESH_BINARY)

    kernel  = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    try:
        opening  = cv2.morphologyEx(thresh_img, cv2.MORPH_OPEN,  kernel)
        closing  = cv2.morphologyEx(opening,    cv2.MORPH_CLOSE, kernel)
        th_frame = 255 - closing
    except Exception:
        th_frame = 255 - blurred

    contours, _ = cv2.findContours(th_frame, cv2.RETR_TREE, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return None

    hull    = [cv2.convexHull(cnt, False) for cnt in contours]
    maxcnt  = max(hull, key=cv2.contourArea)

    result = _fit_rotated_ellipse_ransac(maxcnt.reshape(-1, 2), _rng)
    if result is None:
        return None

    cx, cy, ew, eh, theta = result

    # Sanity-check: centre inside image, axes reasonable
    if not (2 < cx < w-2 and 2 < cy < h-2):
        return None
    if ew < 2 or eh < 2 or ew > w/2 or eh > h/2:
        return None

    if frame_for_draw is not None:
        try:
            cv2.ellipse(frame_for_draw,
                        (int(cx), int(cy)), (max(1, int(ew)), max(1, int(eh))),
                        math.degrees(theta), 0, 360, (0, 255, 0), 2)
            cv2.circle(frame_for_draw, (int(cx), int(cy)), 3, (0, 255, 0), -1)
        except Exception:
            pass
        # Show threshold image in corner
        small_th = cv2.resize(th_frame, (w//2, h//2))
        frame_for_draw[:h//2, :w//2] = cv2.cvtColor(small_th, cv2.COLOR_GRAY2BGR)

    return cx, cy, ew, eh, theta


# ── pye3d 3D gaze model ────────────────────────────────────────────────────────

class GazeModel3D:
    """
    Wraps pye3d Detector3D.  Feed 2D RANSAC results each frame;
    after ~100 frames the 3D eye globe model converges and theta/phi
    gaze angles become reliable.
    """

    def __init__(self, focal_length, w, h):
        cam = CameraModel(focal_length=focal_length, resolution=(w, h))
        self.detector  = Detector3D(camera=cam, long_term_mode=DetectorMode.blocking)
        self._frame_n  = 0
        self._fps      = 60.0
        self._t0       = time.time()

    def process(self, pupil, gray):
        """
        pupil: (cx, cy, w, h, theta_rad)
        Returns (theta, phi) gaze angles in radians, or None.
        theta ≈ π/2 and phi ≈ -π/2 when looking straight at camera.
        model_confidence rises toward 1.0 as the 3D model converges.
        """
        cx, cy, ew, eh, angle_rad = pupil
        ts = time.time() - self._t0
        self._frame_n += 1

        result_2d = {
            'ellipse': {
                'center': (float(cx), float(cy)),
                'axes':   (float(ew), float(eh)),
                'angle':  math.degrees(float(angle_rad)),
            },
            'diameter':   float(ew),
            'location':   (float(cx), float(cy)),
            'confidence': 0.99,
            'timestamp':  ts,
        }
        try:
            r = self.detector.update_and_detect(result_2d, gray)
            return r['theta'], r['phi'], r['model_confidence']
        except Exception:
            return None

    def reset(self):
        """Re-initialise the 3D model (called when camera changes)."""
        self.detector.reset()
        self._frame_n = 0


# ── Warmup-based gaze mapper ───────────────────────────────────────────────────

class GazeMapper:
    """
    Learns the neutral gaze (median theta/phi during warmup) then maps
    (theta - neutral, phi - neutral) to screen coordinates.

    Scale is set from GAZE_RANGE_H/V_DEG (assumed ±N° maps to full screen).
    Adjust with [/] keys.
    """

    def __init__(self, sw, sh, range_h=GAZE_RANGE_H, range_v=GAZE_RANGE_V,
                 n_warmup=WARMUP_FRAMES):
        self.sw       = sw
        self.sh       = sh
        self.n_warmup = n_warmup
        self._buf     = []          # (theta, phi) during warmup
        self._done    = False
        self.neutral_theta = 0.0
        self.neutral_phi   = 0.0
        self._set_range(range_h, range_v)

    def _set_range(self, h_deg, v_deg):
        self.range_h_deg = h_deg
        self.range_v_deg = v_deg
        rh = math.radians(h_deg)
        rv = math.radians(v_deg)
        self.scale_h = sw / (2 * rh)   # px per radian
        self.scale_v = sh / (2 * rv)

    def adjust_scale(self, factor):
        self.scale_h *= factor
        self.scale_v *= factor

    def feed(self, theta, phi):
        if self._done: return
        self._buf.append((theta, phi))
        if len(self._buf) >= self.n_warmup:
            self._finish()

    def _finish(self):
        arr = np.array(self._buf)
        self.neutral_theta = float(np.median(arr[:, 0]))
        self.neutral_phi   = float(np.median(arr[:, 1]))
        self._done = True
        print(f"\nWarmup done. Neutral: θ={math.degrees(self.neutral_theta):.1f}° "
              f"φ={math.degrees(self.neutral_phi):.1f}°")
        print(f"Scale: {self.scale_h:.0f}px/rad H, {self.scale_v:.0f}px/rad V")
        print("Use [/] to adjust sensitivity if cursor doesn't reach edges.")

    def map(self, theta, phi):
        dh = theta - self.neutral_theta
        dv = phi   - self.neutral_phi
        sx = self.sw/2 + dh * self.scale_h
        sy = self.sh/2 + dv * self.scale_v
        return float(np.clip(sx, 0, self.sw)), float(np.clip(sy, 0, self.sh))

    @property
    def done(self): return self._done

    @property
    def progress(self): return min(1.0, len(self._buf) / self.n_warmup)

    def save(self):
        np.savez(CAL_FILE,
                 neutral_theta=self.neutral_theta,
                 neutral_phi=self.neutral_phi,
                 scale_h=self.scale_h,
                 scale_v=self.scale_v)
        print(f"Saved → {CAL_FILE}")

    @classmethod
    def load(cls, sw, sh):
        if not CAL_FILE.exists(): return None
        try:
            d  = np.load(CAL_FILE)
            m  = cls(sw, sh)
            m.neutral_theta = float(d["neutral_theta"])
            m.neutral_phi   = float(d["neutral_phi"])
            m.scale_h       = float(d["scale_h"])
            m.scale_v       = float(d["scale_v"])
            m._done         = True
            print(f"Loaded cal from {CAL_FILE}")
            print(f"  Neutral: θ={math.degrees(m.neutral_theta):.1f}° "
                  f"φ={math.degrees(m.neutral_phi):.1f}°")
            return m
        except Exception as ex:
            print(f"Could not load cal: {ex}")
            return None


# ── Kalman filter ──────────────────────────────────────────────────────────────

class GazeKalman:
    def __init__(self, pn=1.0, mn=150.0):
        self.kf = cv2.KalmanFilter(4, 2)
        self.kf.transitionMatrix  = np.array(
            [[1,0,1,0],[0,1,0,1],[0,0,1,0],[0,0,0,1]], dtype=np.float32)
        self.kf.measurementMatrix = np.array(
            [[1,0,0,0],[0,1,0,0]], dtype=np.float32)
        self.meas_noise = mn
        self.kf.processNoiseCov     = np.eye(4, dtype=np.float32) * pn
        self.kf.measurementNoiseCov = np.eye(2, dtype=np.float32) * mn
        self.kf.errorCovPost        = np.eye(4, dtype=np.float32) * 1000.0
        self._init = False

    def set_mn(self, mn):
        self.meas_noise = mn
        self.kf.measurementNoiseCov = np.eye(2, dtype=np.float32) * mn

    def update(self, x, y):
        if not self._init:
            self.kf.statePost = np.array([[x],[y],[0.],[0.]], dtype=np.float32)
            self._init = True
        self.kf.predict()
        c = self.kf.correct(np.array([[np.float32(x)],[np.float32(y)]]))
        return float(c[0,0]), float(c[1,0])

    def predict_only(self):
        if not self._init: return None
        p = self.kf.predict()
        return float(p[0,0]), float(p[1,0])


# ── Warmup overlay ─────────────────────────────────────────────────────────────

class WarmupWindow:
    WIN = "gaze-warmup"
    def __init__(self, sw, sh):
        self.sw, self.sh = sw, sh
        cv2.namedWindow(self.WIN, cv2.WINDOW_NORMAL)
        cv2.setWindowProperty(self.WIN, cv2.WND_PROP_FULLSCREEN,
                              cv2.WINDOW_FULLSCREEN)

    def draw(self, progress, model_conf):
        img = np.zeros((self.sh, self.sw, 3), dtype=np.uint8)
        bw  = int(self.sw * 0.6)
        bx  = (self.sw - bw) // 2
        by  = self.sh // 2
        cv2.rectangle(img, (bx, by), (bx+bw, by+30), (60,60,60), -1)
        cv2.rectangle(img, (bx, by), (bx+int(bw*progress), by+30), (0,200,80), -1)
        cv2.putText(img, "WARMUP — move your eyes to all corners",
                    (self.sw//2-300, by-30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (200,200,200), 2)
        cv2.putText(img, f"3D model confidence: {model_conf:.0%}",
                    (self.sw//2-180, by+65),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (120,200,120), 1)
        cv2.putText(img, f"{int(progress*100)}%",
                    (self.sw//2-30, by+100),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (180,180,180), 2)
        cv2.imshow(self.WIN, img)

    def close(self):
        try: cv2.destroyWindow(self.WIN)
        except: pass


# ── Dwell clicker ──────────────────────────────────────────────────────────────

class DwellClicker:
    def __init__(self, s, r): self.s=s; self.r=r; self._o=self._t=None
    def update(self, x, y):
        if self.s<=0: return False
        now=time.time()
        if self._o is None: self._o=(x,y); self._t=now; return False
        if math.hypot(x-self._o[0],y-self._o[1])>self.r:
            self._o=(x,y); self._t=now; return False
        if now-self._t>=self.s: self._o=self._t=None; return True
        return False


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    global sw, sh   # needed by GazeMapper.load closure

    parser = argparse.ArgumentParser()
    parser.add_argument("camera",      nargs="?", type=int, default=CAMERA_INDEX)
    parser.add_argument("--no-preview",action="store_true")
    parser.add_argument("--skip-load", action="store_true")
    parser.add_argument("--gaze-pipe", default=None, metavar="PATH",
                        help="Write 'theta phi\\n' every frame to this path")
    args = parser.parse_args()

    sw, sh = SCREEN_W, SCREEN_H

    # ── Camera ──
    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        print(f"ERROR: Cannot open camera {args.camera}"); sys.exit(1)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  CAMERA_W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_H)
    cap.set(cv2.CAP_PROP_FPS, CAMERA_FPS)
    aw  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    ah  = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    print(f"Camera {args.camera}: {aw}×{ah} @ {fps:.0f}fps")

    # ── Gaze pipe ──
    gaze_pipe = None
    if args.gaze_pipe:
        import os
        p = Path(args.gaze_pipe)
        if not p.exists(): os.mkfifo(str(p))
        gaze_pipe = open(str(p), "w", buffering=1)
        print(f"Gaze pipe: {args.gaze_pipe}")

    # ── Subsystems ──
    ui      = create_uinput_mouse()
    model   = GazeModel3D(CAMERA_FX, aw, ah)
    kalman  = GazeKalman(KALMAN_PROCESS_NOISE, KALMAN_MEAS_NOISE)
    dwell   = DwellClicker(DWELL_SECONDS, DWELL_RADIUS)

    # ── Mutable state ──
    thresh_add  = THRESH_ADD
    flip_x      = FLIP_X
    flip_y      = FLIP_Y
    paused      = False
    cursor_x    = float(sw) / 2
    cursor_y    = float(sh) / 2
    prev_cx     = cursor_x
    prev_cy     = cursor_y
    model_conf  = 0.0

    fps_buf  = deque(maxlen=30)
    last_t   = time.time()

    # ── Mapper: load saved or start warmup ──
    mapper     = None
    warmup_win = None
    if not args.skip_load:
        mapper = GazeMapper.load(sw, sh)

    if mapper is None:
        print("\nStarting warmup — look around and move your eyes to all corners.")
        mapper     = GazeMapper(sw, sh)
        warmup_win = WarmupWindow(sw, sh)

    show_preview = SHOW_PREVIEW and not args.no_preview
    if show_preview:
        cv2.namedWindow("Gaze Mouse", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("Gaze Mouse",
                         int(aw * PREVIEW_SCALE), int(ah * PREVIEW_SCALE))

    print("\nControls:")
    print("  W — redo warmup    A — save cal")
    print("  P — pause/resume   F — flip X   V — flip Y")
    print("  +/- — RANSAC threshold   [/] — gaze sensitivity")
    print("  Q/ESC — quit\n")

    while True:
        ret, frame = cap.read()
        if not ret:
            print("Camera read failed"); break

        gray    = (frame if len(frame.shape)==2 else
                   frame[:,:,0] if frame.shape[2]==1 else
                   cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
        display = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
        h_, w_  = gray.shape

        now = time.time()
        fps_buf.append(now - last_t); last_t = now
        measured_fps = len(fps_buf) / max(sum(fps_buf), 1e-6)

        # ── Pupil detection ──
        pupil = detect_pupil_ransac(gray, thresh_add, display)

        # ── 3D gaze model ──
        gaze = None
        if pupil is not None:
            result = model.process(pupil, gray)
            if result is not None:
                theta_raw, phi_raw, model_conf = result
                # Apply flips (negate = mirror)
                theta = -theta_raw if flip_x else theta_raw
                phi   = -phi_raw   if flip_y else phi_raw
                gaze  = (theta, phi)

        # ── Warmup ──
        if not mapper.done:
            if gaze is not None:
                mapper.feed(*gaze)
            if mapper.done and warmup_win is not None:
                warmup_win.close(); warmup_win = None
            if warmup_win is not None:
                warmup_win.draw(mapper.progress, model_conf)

        # ── Map to screen ──
        if gaze is not None and mapper.done:
            sx, sy = mapper.map(*gaze)
            cursor_x, cursor_y = kalman.update(sx, sy)
        else:
            r = kalman.predict_only()
            if r: cursor_x, cursor_y = r

        # ── Mouse injection ──
        if mapper.done and not paused and ui is not None:
            dx = int(round(cursor_x - prev_cx))
            dy = int(round(cursor_y - prev_cy))
            mouse_move(ui, dx, dy)
            if gaze and dwell.update(cursor_x, cursor_y):
                mouse_click(ui)

        prev_cx, prev_cy = cursor_x, cursor_y

        # ── Gaze pipe ──
        if gaze_pipe and gaze:
            gaze_pipe.write(f"{gaze[0]:.6f} {gaze[1]:.6f}\n")

        # ── Preview HUD ──
        if show_preview:
            if not mapper.done:
                status = f"WARMUP {int(mapper.progress*100)}%"
                col    = (0, 200, 255)
            elif paused:
                status = "PAUSED"; col = (0, 140, 255)
            else:
                status = f"TRACKING  conf:{model_conf:.0%}"; col = (0, 255, 100)

            cv2.putText(display, f"{status}  {measured_fps:.0f}fps",
                        (5, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.55, col, 1)
            cv2.putText(display,
                        f"thr:{thresh_add:+d}  K:{kalman.meas_noise:.0f}  "
                        f"{'FX ' if flip_x else ''}{'FY' if flip_y else ''}",
                        (5, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (180,180,180), 1)
            if gaze:
                cv2.putText(display,
                            f"θ={math.degrees(gaze[0]):.1f}°  "
                            f"φ={math.degrees(gaze[1]):.1f}°  "
                            f"cursor:({cursor_x:.0f},{cursor_y:.0f})",
                            (5, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (180,180,180), 1)
            else:
                cv2.putText(display, "NO PUPIL",
                            (5, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0,100,220), 1)

            scaled = cv2.resize(display,
                                (int(w_*PREVIEW_SCALE), int(h_*PREVIEW_SCALE)),
                                interpolation=cv2.INTER_NEAREST)
            cv2.imshow("Gaze Mouse", scaled)

        # ── Keys ──
        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            break
        elif key == ord('w'):
            mapper = GazeMapper(sw, sh)
            model.reset()
            warmup_win = WarmupWindow(sw, sh)
            print("Warmup restarted.")
        elif key == ord('a'):
            if mapper.done:
                mapper.save()
            else:
                print("Warmup not done yet.")
        elif key == ord('p'):
            paused = not paused
            print("Paused" if paused else "Resumed")
        elif key == ord('f'):
            flip_x = not flip_x
            mapper = GazeMapper(sw, sh)
            model.reset()
            warmup_win = WarmupWindow(sw, sh)
            print(f"Flip X: {flip_x} — warmup restarted")
        elif key == ord('v'):
            flip_y = not flip_y
            mapper = GazeMapper(sw, sh)
            model.reset()
            warmup_win = WarmupWindow(sw, sh)
            print(f"Flip Y: {flip_y} — warmup restarted")
        elif key in (ord('+'), ord('=')):
            thresh_add = min(200, thresh_add + 2)
            print(f"thresh_add: {thresh_add}")
        elif key == ord('-'):
            thresh_add = max(1, thresh_add - 2)
            print(f"thresh_add: {thresh_add}")
        elif key == ord('['):
            mapper.adjust_scale(0.8)
            print(f"Sensitivity -20%  scale_h={mapper.scale_h:.0f}")
        elif key == ord(']'):
            mapper.adjust_scale(1.25)
            print(f"Sensitivity +25%  scale_h={mapper.scale_h:.0f}")

    # ── Cleanup ──
    cap.release()
    cv2.destroyAllWindows()
    if ui: ui.close()
    if gaze_pipe: gaze_pipe.close()
    print("Done.")


if __name__ == "__main__":
    main()
