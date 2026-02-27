/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QObject>
#include <QThread>
#include <QtQmlIntegration>

class SysInfoWorker;

/**
 * Polls RK3588S system statistics (CPU freq/temp/load, GPU freq/load/temp,
 * RAM usage) via sysfs/procfs once per second and exposes them as QML properties.
 *
 * All blocking sysfs I/O happens on a dedicated background thread so the
 * KWin render thread is never stalled.
 *
 * Frame timing (fps, frameTimeMs) is updated by the QML side via recordFrame().
 */
class KwinVrSysInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int cpuFreqBigMhz    READ cpuFreqBigMhz    NOTIFY statsUpdated)
    Q_PROPERTY(int cpuFreqLittleMhz READ cpuFreqLittleMhz NOTIFY statsUpdated)
    Q_PROPERTY(int cpuUsagePercent  READ cpuUsagePercent  NOTIFY statsUpdated)
    Q_PROPERTY(int cpuTempC         READ cpuTempC         NOTIFY statsUpdated)
    Q_PROPERTY(int gpuFreqMhz       READ gpuFreqMhz       NOTIFY statsUpdated)
    Q_PROPERTY(int gpuLoadPercent   READ gpuLoadPercent   NOTIFY statsUpdated)
    Q_PROPERTY(int gpuTempC         READ gpuTempC         NOTIFY statsUpdated)
    Q_PROPERTY(int ramUsedMb        READ ramUsedMb        NOTIFY statsUpdated)
    Q_PROPERTY(int ramTotalMb       READ ramTotalMb       NOTIFY statsUpdated)
    Q_PROPERTY(qreal fps            READ fps              NOTIFY frameStatsUpdated)
    Q_PROPERTY(qreal frameTimeMs    READ frameTimeMs      NOTIFY frameStatsUpdated)
    Q_PROPERTY(bool active          READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit KwinVrSysInfo(QObject *parent = nullptr);
    ~KwinVrSysInfo() override;

    int   cpuFreqBigMhz()    const { return m_cpuFreqBigMhz; }
    int   cpuFreqLittleMhz() const { return m_cpuFreqLittleMhz; }
    int   cpuUsagePercent()  const { return m_cpuUsagePercent; }
    int   cpuTempC()         const { return m_cpuTempC; }
    int   gpuFreqMhz()       const { return m_gpuFreqMhz; }
    int   gpuLoadPercent()   const { return m_gpuLoadPercent; }
    int   gpuTempC()         const { return m_gpuTempC; }
    int   ramUsedMb()        const { return m_ramUsedMb; }
    int   ramTotalMb()       const { return m_ramTotalMb; }
    qreal fps()              const { return m_fps; }
    qreal frameTimeMs()      const { return m_frameTimeMs; }
    bool  active()           const { return m_active; }

    void setActive(bool a);

    /** Call once per rendered VR frame with the elapsed time in seconds. */
    Q_INVOKABLE void recordFrame(qreal elapsedSecs);

Q_SIGNALS:
    void statsUpdated();
    void frameStatsUpdated();
    void activeChanged();

    // Internal: sent to worker thread to start/stop polling
    void startPolling();
    void stopPolling();

private Q_SLOTS:
    void onStatsReady(int cpuBigMhz, int cpuLittleMhz, int cpuUsage, int cpuTempC,
                      int gpuFreqMhz, int gpuLoad, int gpuTempC,
                      int ramUsedMb, int ramTotalMb);

private:
    SysInfoWorker *m_worker       = nullptr;
    QThread       *m_workerThread = nullptr;
    bool           m_active       = false;

    // Cached values (written on main thread from queued signal)
    int m_cpuFreqBigMhz    = 0;
    int m_cpuFreqLittleMhz = 0;
    int m_cpuUsagePercent  = 0;
    int m_cpuTempC         = 0;
    int m_gpuFreqMhz       = 0;
    int m_gpuLoadPercent   = 0;
    int m_gpuTempC         = 0;
    int m_ramUsedMb        = 0;
    int m_ramTotalMb       = 0;

    // Frame timing (main thread only)
    qreal m_fps         = 0.0;
    qreal m_frameTimeMs = 0.0;
    qreal m_frameAccum  = 0.0;
    int   m_frameCount  = 0;
};
