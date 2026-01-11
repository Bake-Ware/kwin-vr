/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVRCONFIGWRAPPER_H
#define KWINVRCONFIGWRAPPER_H
#include "kwinvrconfig.h"
#include <QQmlApplicationEngine>
namespace KWin
{

class KWinVRConfigWrapper : public KWin::KWinVRConfig
{
    Q_OBJECT
    QML_SINGLETON
    QML_NAMED_ELEMENT(KWinVRConfig)
public:
    static KWinVRConfigWrapper *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
    {
        Q_UNUSED(qmlEngine);
        Q_UNUSED(jsEngine);
        auto config = instance();
        QQmlEngine::setObjectOwnership(config, QQmlEngine::CppOwnership);
        return config;
    }
    static KWinVRConfigWrapper *instance()
    {
        static KWinVRConfigWrapper inst;
        return &inst;
    }

protected:
    KWinVRConfigWrapper(QObject *parent = nullptr)
        : KWinVRConfig(parent)
    {
    }
};
}

#endif // KWINVRCONFIGWRAPPER_H
