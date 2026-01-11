/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "main.h"
#include "kwinvr.h"
#include <KPluginFactory>
#include <QObject>
#include <plugin.h>

using namespace KWin;

class KWIN_EXPORT KwinVrManagerFactory : public PluginFactory
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID PluginFactory_iid FILE "metadata.json")
    Q_INTERFACES(KWin::PluginFactory)

public:
    explicit KwinVrManagerFactory() = default;

    std::unique_ptr<Plugin> create() const override;
};

std::unique_ptr<Plugin> KwinVrManagerFactory::create() const
{
    return std::make_unique<KwinVr>();
}

#include "main.moc"
