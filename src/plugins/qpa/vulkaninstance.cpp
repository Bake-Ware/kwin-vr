/*
    SPDX-FileCopyrightText: 2026 KWin VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vulkaninstance.h"

namespace KWin
{
namespace QPA
{

VulkanInstance::VulkanInstance(QVulkanInstance *instance)
    : m_instance(instance)
{
    loadVulkanLibrary(QStringLiteral("vulkan"), 1);
}

void VulkanInstance::createOrAdoptInstance()
{
    initInstance(m_instance, {});
}

bool VulkanInstance::supportsPresent(VkPhysicalDevice, uint32_t, QWindow *)
{
    // No window presentation needed — VR uses OpenXR swapchains
    return false;
}

} // namespace QPA
} // namespace KWin
