/*
    SPDX-FileCopyrightText: 2026 KWin VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QtGui/private/qbasicvulkanplatforminstance_p.h>

namespace KWin
{
namespace QPA
{

class VulkanInstance : public QBasicPlatformVulkanInstance
{
public:
    explicit VulkanInstance(QVulkanInstance *instance);

    void createOrAdoptInstance() override;
    bool supportsPresent(VkPhysicalDevice physicalDevice, uint32_t queueFamilyIndex, QWindow *window) override;

private:
    QVulkanInstance *m_instance = nullptr;
};

} // namespace QPA
} // namespace KWin
