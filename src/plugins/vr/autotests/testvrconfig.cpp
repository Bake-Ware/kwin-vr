/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrconfig.h"

#include <QStandardPaths>
#include <QTest>

using namespace KWin;

class TestVrConfig : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // Never touch the user's real kwinvr config
        QStandardPaths::setTestModeEnabled(true);
    }

    void defaultsMatchKcfg()
    {
        KWinVRConfig config;
        config.setDefaults();
        // These defaults are load-bearing: PPU drives window physical size,
        // width/height define the virtual screen template (see kwinvr.kcfg)
        QCOMPARE(config.width(), 1440);
        QCOMPARE(config.height(), 900);
        QCOMPARE(config.ppu(), 20);
        QCOMPARE(config.distance(), 100);
        QCOMPARE(config.hudEnabled(), false);
        QCOMPARE(config.followEnabled(), true);
    }

    void defaultValueGettersAgreeWithDefaults()
    {
        KWinVRConfig config;
        config.setDefaults();
        QCOMPARE(config.width(), config.defaultWidthValue());
        QCOMPARE(config.height(), config.defaultHeightValue());
        QCOMPARE(config.ppu(), config.defaultPpuValue());
    }

    void roundTripPersists()
    {
        {
            KWinVRConfig config;
            config.setDefaults();
            config.setWidth(2560);
            config.setHeight(1440);
            config.setHudEnabled(true);
            QVERIFY(config.save());
        }
        {
            KWinVRConfig config;
            config.load();
            QCOMPARE(config.width(), 2560);
            QCOMPARE(config.height(), 1440);
            QCOMPARE(config.hudEnabled(), true);
        }
        // restore defaults on disk for repeat runs
        KWinVRConfig config;
        config.setDefaults();
        QVERIFY(config.save());
    }
};

QTEST_GUILESS_MAIN(TestVrConfig)
#include "testvrconfig.moc"
