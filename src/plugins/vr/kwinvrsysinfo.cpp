/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrsysinfo.h"

#include <QFile>
#include <QTimer>

// ── sysfs paths for RK3588S ──────────────────────────────────────────────────
static constexpr const char *kCpuFreqBig    = "/sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq";
static constexpr const char *kCpuFreqLittle = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq";
static constexpr const char *kCpuTempPath   = "/sys/class/thermal/thermal_zone1/temp";
static constexpr const char *kGpuTempPath   = "/sys/class/thermal/thermal_zone5/temp";
static constexpr const char *kGpuLoadPath   = "/sys/class/devfreq/fb000000.gpu/load";

// ── Background worker — lives on m_workerThread ───────────────────────────────

class SysInfoWorker : public QObject
{
    Q_OBJECT
public:
    explicit SysInfoWorker(QObject *parent = nullptr) : QObject(parent)
    {
        m_timer.setInterval(1000);
        connect(&m_timer, &QTimer::timeout, this, &SysInfoWorker::poll);
    }

public Q_SLOTS:
    void start()
    {
        // Prime CPU baseline before first delta
        readCpuJiffies(m_prevIdle, m_prevTotal);
        poll();
        m_timer.start();
    }

    void stop()
    {
        m_timer.stop();
    }

Q_SIGNALS:
    void statsReady(int cpuBigMhz, int cpuLittleMhz, int cpuUsage, int cpuTempC,
                    int gpuFreqMhz, int gpuLoad, int gpuTempC,
                    int ramUsedMb, int ramTotalMb);

private:
    static int readInt(const char *path)
    {
        QFile f(QString::fromLatin1(path));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            return -1;
        return f.readLine().trimmed().toInt();
    }

    static QString readLine(const char *path)
    {
        QFile f(QString::fromLatin1(path));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            return {};
        return QString::fromLatin1(f.readLine().trimmed());
    }

    static void readCpuJiffies(quint64 &idle, quint64 &total)
    {
        QFile f(QStringLiteral("/proc/stat"));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            return;
        QString line;
        while (!f.atEnd()) {
            line = QString::fromLatin1(f.readLine());
            if (line.startsWith(QLatin1String("cpu ")))
                break;
        }
        const QStringList p = line.split(u' ', Qt::SkipEmptyParts);
        if (p.size() < 5)
            return;
        quint64 user    = p[1].toULongLong();
        quint64 nice    = p[2].toULongLong();
        quint64 system  = p[3].toULongLong();
        quint64 idleJ   = p[4].toULongLong();
        quint64 iowait  = p.size() > 5 ? p[5].toULongLong() : 0;
        quint64 irq     = p.size() > 6 ? p[6].toULongLong() : 0;
        quint64 softirq = p.size() > 7 ? p[7].toULongLong() : 0;
        idle  = idleJ + iowait;
        total = user + nice + system + idleJ + iowait + irq + softirq;
    }

    void poll()
    {
        // CPU frequencies (kHz → MHz)
        const int bigKhz    = readInt(kCpuFreqBig);
        const int littleKhz = readInt(kCpuFreqLittle);
        const int cpuBigMhz    = bigKhz    > 0 ? bigKhz    / 1000 : 0;
        const int cpuLittleMhz = littleKhz > 0 ? littleKhz / 1000 : 0;

        // CPU usage delta
        quint64 nowIdle = 0, nowTotal = 0;
        readCpuJiffies(nowIdle, nowTotal);
        const quint64 dIdle  = nowIdle  - m_prevIdle;
        const quint64 dTotal = nowTotal - m_prevTotal;
        const int cpuUsage = dTotal > 0
            ? static_cast<int>((dTotal - dIdle) * 100 / dTotal) : 0;
        m_prevIdle  = nowIdle;
        m_prevTotal = nowTotal;

        // Temperatures (millidegrees → degrees)
        const int cpuTempRaw = readInt(kCpuTempPath);
        const int gpuTempRaw = readInt(kGpuTempPath);
        const int cpuTempC = cpuTempRaw > 0 ? cpuTempRaw / 1000 : 0;
        const int gpuTempC = gpuTempRaw > 0 ? gpuTempRaw / 1000 : 0;

        // GPU load & freq — format "78@900000000Hz"
        int gpuLoad = 0, gpuFreqMhz = 0;
        const QString gpuLine = readLine(kGpuLoadPath);
        if (!gpuLine.isEmpty()) {
            const int at = gpuLine.indexOf(u'@');
            if (at > 0) {
                gpuLoad = gpuLine.left(at).toInt();
                QString freqStr = gpuLine.mid(at + 1);
                if (freqStr.endsWith(QLatin1String("Hz"), Qt::CaseInsensitive))
                    freqStr.chop(2);
                gpuFreqMhz = static_cast<int>(freqStr.toULongLong() / 1'000'000);
            }
        }

        // RAM (kB → MB)
        int ramTotalMb = 0, ramUsedMb = 0;
        QFile meminfo(QStringLiteral("/proc/meminfo"));
        if (meminfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
            quint64 total = 0, available = 0;
            while (!meminfo.atEnd()) {
                const QString line = QString::fromLatin1(meminfo.readLine());
                if (line.startsWith(QLatin1String("MemTotal:")))
                    total = line.split(u' ', Qt::SkipEmptyParts)[1].toULongLong();
                else if (line.startsWith(QLatin1String("MemAvailable:")))
                    available = line.split(u' ', Qt::SkipEmptyParts)[1].toULongLong();
                if (total && available)
                    break;
            }
            ramTotalMb = static_cast<int>(total / 1024);
            ramUsedMb  = static_cast<int>((total - available) / 1024);
        }

        Q_EMIT statsReady(cpuBigMhz, cpuLittleMhz, cpuUsage, cpuTempC,
                          gpuFreqMhz, gpuLoad, gpuTempC, ramUsedMb, ramTotalMb);
    }

    QTimer  m_timer;
    quint64 m_prevIdle  = 0;
    quint64 m_prevTotal = 0;
};

#include "kwinvrsysinfo.moc"

// ── KwinVrSysInfo ─────────────────────────────────────────────────────────────

KwinVrSysInfo::KwinVrSysInfo(QObject *parent)
    : QObject(parent)
{
    m_workerThread = new QThread(this);
    m_worker       = new SysInfoWorker();   // no parent — will be moved to thread
    m_worker->moveToThread(m_workerThread);

    // Queued connection: statsReady() crosses thread boundary to main thread
    connect(m_worker, &SysInfoWorker::statsReady,
            this, &KwinVrSysInfo::onStatsReady,
            Qt::QueuedConnection);

    // start/stop signals are also queued (worker thread event loop handles them)
    connect(this, &KwinVrSysInfo::startPolling,
            m_worker, &SysInfoWorker::start,
            Qt::QueuedConnection);
    connect(this, &KwinVrSysInfo::stopPolling,
            m_worker, &SysInfoWorker::stop,
            Qt::QueuedConnection);

    // Clean up worker when thread finishes
    connect(m_workerThread, &QThread::finished,
            m_worker, &QObject::deleteLater);

    m_workerThread->start();
}

KwinVrSysInfo::~KwinVrSysInfo()
{
    Q_EMIT stopPolling();
    m_workerThread->quit();
    m_workerThread->wait();
}

void KwinVrSysInfo::setActive(bool a)
{
    if (m_active == a)
        return;
    m_active = a;
    if (m_active)
        Q_EMIT startPolling();
    else
        Q_EMIT stopPolling();
    Q_EMIT activeChanged();
}

void KwinVrSysInfo::recordFrame(qreal elapsedSecs)
{
    if (elapsedSecs <= 0.0 || elapsedSecs > 1.0)
        return;

    m_frameAccum += elapsedSecs;
    ++m_frameCount;

    if (m_frameAccum >= 0.5) {
        m_fps         = m_frameCount / m_frameAccum;
        m_frameTimeMs = (m_frameAccum / m_frameCount) * 1000.0;
        m_frameAccum  = 0.0;
        m_frameCount  = 0;
        Q_EMIT frameStatsUpdated();
    }
}

void KwinVrSysInfo::onStatsReady(int cpuBigMhz, int cpuLittleMhz, int cpuUsage, int cpuTempC,
                                  int gpuFreqMhz, int gpuLoad, int gpuTempC,
                                  int ramUsedMb, int ramTotalMb)
{
    m_cpuFreqBigMhz    = cpuBigMhz    > 0 ? cpuBigMhz    : m_cpuFreqBigMhz;
    m_cpuFreqLittleMhz = cpuLittleMhz > 0 ? cpuLittleMhz : m_cpuFreqLittleMhz;
    m_cpuUsagePercent  = cpuUsage;
    m_cpuTempC         = cpuTempC     > 0 ? cpuTempC     : m_cpuTempC;
    m_gpuFreqMhz       = gpuFreqMhz   > 0 ? gpuFreqMhz   : m_gpuFreqMhz;
    m_gpuLoadPercent   = gpuLoad;
    m_gpuTempC         = gpuTempC     > 0 ? gpuTempC     : m_gpuTempC;
    m_ramUsedMb        = ramUsedMb    > 0 ? ramUsedMb    : m_ramUsedMb;
    m_ramTotalMb       = ramTotalMb   > 0 ? ramTotalMb   : m_ramTotalMb;
    Q_EMIT statsUpdated();
}
