/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "../spaceallocator3d.h"

#include <QSizeF>
#include <QTest>
#include <QtQuick3D/private/qquick3dnode_p.h>

using namespace KWin;

// SpaceAllocator3D reads object size via QQmlProperty(sizePropertyName), which
// resolves meta-object properties — so the test node declares itemSize properly.
class SizedNode : public QQuick3DNode
{
    Q_OBJECT
    Q_PROPERTY(QSizeF itemSize READ itemSize WRITE setItemSize NOTIFY itemSizeChanged)
public:
    explicit SizedNode(QObject *parent = nullptr)
    {
        Q_UNUSED(parent)
    }
    QSizeF itemSize() const
    {
        return m_size;
    }
    void setItemSize(const QSizeF &s)
    {
        m_size = s;
        Q_EMIT itemSizeChanged();
    }
Q_SIGNALS:
    void itemSizeChanged();

private:
    QSizeF m_size;
};

class TestSpaceAllocator3D : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void firstAllocationIsCenteredAtDistance()
    {
        // No viewpoint: basis is origin facing -Z. No tracked objects:
        // the first (center-most) candidate must win.
        SpaceAllocator3D alloc;
        alloc.setDistance(150.0);
        const QVector3D pos = alloc.findFreePosition(60, 40);
        QVERIFY((pos - QVector3D(0, 0, -150)).length() < 1.0f);
    }

    void distancePropertyIsRespected()
    {
        SpaceAllocator3D alloc;
        alloc.setDistance(300.0);
        const QVector3D pos = alloc.findFreePosition(60, 40);
        QVERIFY(qAbs(pos.length() - 300.0f) < 1.0f);
    }

    void occupiedCenterPushesSecondAllocationAside()
    {
        SpaceAllocator3D alloc;
        alloc.setDistance(150.0);

        SizedNode occupant;
        occupant.setItemSize(QSizeF(60, 40));
        occupant.setPosition(QVector3D(0, 0, -150)); // dead center
        alloc.registerObject(&occupant);

        const QVector3D pos = alloc.findFreePosition(60, 40);
        // Must still sit on the sphere...
        QVERIFY(qAbs(pos.length() - 150.0f) < 1.0f);
        // ...but not at the occupied center
        QVERIFY((pos - QVector3D(0, 0, -150)).length() > 10.0f);
    }

    void unregisterFreesTheCenter()
    {
        SpaceAllocator3D alloc;
        alloc.setDistance(150.0);

        SizedNode occupant;
        occupant.setItemSize(QSizeF(60, 40));
        occupant.setPosition(QVector3D(0, 0, -150));
        alloc.registerObject(&occupant);
        alloc.unregisterObject(&occupant);

        const QVector3D pos = alloc.findFreePosition(60, 40);
        QVERIFY((pos - QVector3D(0, 0, -150)).length() < 1.0f);
    }

    void destroyedObjectIsNotConsidered()
    {
        SpaceAllocator3D alloc;
        alloc.setDistance(150.0);
        {
            auto *occupant = new SizedNode;
            occupant->setItemSize(QSizeF(60, 40));
            occupant->setPosition(QVector3D(0, 0, -150));
            alloc.registerObject(occupant);
            delete occupant; // allocator must survive object deletion
        }
        const QVector3D pos = alloc.findFreePosition(60, 40);
        QVERIFY((pos - QVector3D(0, 0, -150)).length() < 1.0f);
    }

    void twoOccupantsLeaveDistinctFreeSpots()
    {
        SpaceAllocator3D alloc;
        alloc.setDistance(150.0);

        SizedNode a;
        a.setItemSize(QSizeF(60, 40));
        a.setPosition(QVector3D(0, 0, -150));
        alloc.registerObject(&a);

        const QVector3D posB = alloc.findFreePosition(60, 40);
        SizedNode b;
        b.setItemSize(QSizeF(60, 40));
        b.setPosition(posB);
        alloc.registerObject(&b);

        const QVector3D posC = alloc.findFreePosition(60, 40);
        QVERIFY((posC - QVector3D(0, 0, -150)).length() > 10.0f);
        QVERIFY((posC - posB).length() > 10.0f);
    }
};

QTEST_GUILESS_MAIN(TestSpaceAllocator3D)
#include "testspaceallocator3d.moc"
