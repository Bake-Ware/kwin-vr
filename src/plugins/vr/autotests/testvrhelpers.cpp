/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "../kwinvrhelpers.h"

#include <QTest>
#include <QVector2D>
#include <QVector3D>

using namespace KWin;

static bool fuzzyEqual(const QVector3D &a, const QVector3D &b, float eps = 1e-4f)
{
    return (a - b).length() < eps;
}

class TestVrHelpers : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // --- rayPlaneIntersection ---

    void rayPlaneHitsStraightOn()
    {
        // Ray from origin down -Z into a plane facing +Z at z=-100
        const auto r = KwinVrHelpers::rayPlaneIntersection(
            {0, 0, 0}, {0, 0, -1}, {0, 0, -100}, {0, 0, 1});
        QVERIFY(r.valid);
        QVERIFY(fuzzyEqual(r.position, {0, 0, -100}));
        QCOMPARE(r.distance, 100.0f);
    }

    void rayPlaneHitsAtAngle()
    {
        // 45° ray in the XZ plane: equal parts +X and -Z
        const float inv = 1.0f / std::sqrt(2.0f);
        const auto r = KwinVrHelpers::rayPlaneIntersection(
            {0, 0, 0}, {inv, 0, -inv}, {0, 0, -100}, {0, 0, 1});
        QVERIFY(r.valid);
        QVERIFY(fuzzyEqual(r.position, {100, 0, -100}));
        QVERIFY(qAbs(r.distance - 100.0f * std::sqrt(2.0f)) < 1e-3f);
    }

    void rayPlaneParallelMisses()
    {
        // Ray along +X, plane normal +Z: parallel, no intersection
        const auto r = KwinVrHelpers::rayPlaneIntersection(
            {0, 0, 0}, {1, 0, 0}, {0, 0, -100}, {0, 0, 1});
        QVERIFY(!r.valid);
    }

    void rayPlaneBehindOriginMisses()
    {
        // Plane is behind the ray (t < 0)
        const auto r = KwinVrHelpers::rayPlaneIntersection(
            {0, 0, 0}, {0, 0, -1}, {0, 0, 100}, {0, 0, 1});
        QVERIFY(!r.valid);
    }

    // --- raySphereIntersect ---

    void raySphereThroughCenter()
    {
        // Origin outside, ray through the center of a r=10 sphere at z=-100
        const auto t = KwinVrHelpers::raySphereIntersect(
            {0, 0, 0}, {0, 0, -1}, {0, 0, -100}, 10.0f);
        QVERIFY(qAbs(t.x() - 90.0f) < 1e-3f);
        QVERIFY(qAbs(t.y() - 110.0f) < 1e-3f);
    }

    void raySphereMiss()
    {
        const auto t = KwinVrHelpers::raySphereIntersect(
            {0, 0, 0}, {0, 0, -1}, {100, 0, -100}, 10.0f);
        QCOMPARE(t, QVector2D(-1.0f, -1.0f));
    }

    void raySphereFromInside()
    {
        // Origin at sphere center: t1 negative, t2 positive
        const auto t = KwinVrHelpers::raySphereIntersect(
            {0, 0, 0}, {0, 0, -1}, {0, 0, 0}, 10.0f);
        QVERIFY(qAbs(t.x() + 10.0f) < 1e-3f);
        QVERIFY(qAbs(t.y() - 10.0f) < 1e-3f);
        // ...and Far picks the positive exit point
        const float far = KwinVrHelpers::raySphereIntersectFar(
            {0, 0, 0}, {0, 0, -1}, {0, 0, 0}, 10.0f);
        QVERIFY(qAbs(far - 10.0f) < 1e-3f);
    }

    void raySphereFarBehindReturnsMinusOne()
    {
        // Sphere entirely behind the ray origin
        const float far = KwinVrHelpers::raySphereIntersectFar(
            {0, 0, 0}, {0, 0, -1}, {0, 0, 100}, 10.0f);
        QCOMPARE(far, -1.0f);
    }

    // --- rotation helpers ---

    void rotationBetweenVectorsRotates()
    {
        const auto q = KwinVrHelpers::rotationBetweenVectors({0, 0, -1}, {1, 0, 0});
        QVERIFY(fuzzyEqual(q.rotatedVector({0, 0, -1}), {1, 0, 0}));
    }

    void rotationBetweenIdenticalVectorsIsIdentity()
    {
        const auto q = KwinVrHelpers::rotationBetweenVectors({0, 0, -1}, {0, 0, -1});
        QVERIFY(fuzzyEqual(q.rotatedVector({0, 1, 0}), {0, 1, 0}));
        QVERIFY(fuzzyEqual(q.rotatedVector({1, 0, 0}), {1, 0, 0}));
    }

    void rotationDeltaRoundTrip()
    {
        const auto src = QQuaternion::fromAxisAndAngle({0, 1, 0}, 30);
        const auto dst = QQuaternion::fromAxisAndAngle({1, 0, 0}, -70);
        const auto delta = KwinVrHelpers::getRotationDelta(src, dst);
        const auto restored = src * delta;
        // src * delta must equal dst (compare action on a probe vector)
        QVERIFY(fuzzyEqual(restored.rotatedVector({0, 0, -1}),
                           dst.rotatedVector({0, 0, -1})));
        QVERIFY(fuzzyEqual(restored.rotatedVector({0, 1, 0}),
                           dst.rotatedVector({0, 1, 0})));
    }

    void rotateVectorMatchesQuaternion()
    {
        const auto q = QQuaternion::fromAxisAndAngle({0, 1, 0}, 90);
        QVERIFY(fuzzyEqual(KwinVrHelpers::rotateVector(q, {0, 0, -1}),
                           q.rotatedVector({0, 0, -1})));
    }

    void rollAngleZeroWhenAligned()
    {
        const QQuaternion identity;
        const float roll = KwinVrHelpers::rollAngleBetween(identity, {0, 0, -1}, {0, 1, 0});
        QVERIFY(qAbs(roll) < 1e-3f);
    }

    void rotateRelativePoseRotatesBoth()
    {
        const RelativePose pose(QQuaternion(), QVector3D(0, 0, -100));
        const auto q = QQuaternion::fromAxisAndAngle({0, 1, 0}, 90);
        const auto rotated = KwinVrHelpers::rotateRelativePose(pose, q);
        QVERIFY(fuzzyEqual(rotated.position, {-100, 0, 0}));
    }

    // --- key binding helpers ---

    void keyMatchExact()
    {
        QVERIFY(KwinVrHelpers::keyMatch(Qt::Key_A, Qt::ControlModifier, QStringLiteral("Ctrl+A")));
        QVERIFY(!KwinVrHelpers::keyMatch(Qt::Key_A, Qt::NoModifier, QStringLiteral("Ctrl+A")));
        QVERIFY(!KwinVrHelpers::keyMatch(Qt::Key_B, Qt::ControlModifier, QStringLiteral("Ctrl+A")));
    }

    void keyMatchNoneNeverMatches()
    {
        QVERIFY(!KwinVrHelpers::keyMatch(Qt::Key_A, Qt::NoModifier, QStringLiteral("none")));
        QVERIFY(!KwinVrHelpers::keyMatch(Qt::Key_A, Qt::NoModifier, QString()));
    }

    void normalizeKeyCanonicalizes()
    {
        QCOMPARE(KwinVrHelpers::normalizeKey(QStringLiteral("ctrl+shift+a")),
                 QKeySequence(QStringLiteral("ctrl+shift+a"), QKeySequence::PortableText)
                     .toString(QKeySequence::PortableText));
        QCOMPARE(KwinVrHelpers::normalizeKey(QString()), QString());
    }

    void keyToStringRoundTripsThroughKeyMatch()
    {
        const QString s = KwinVrHelpers::keyToString(Qt::Key_F, Qt::ControlModifier | Qt::ShiftModifier);
        QVERIFY(!s.isEmpty());
        QVERIFY(KwinVrHelpers::keyMatch(Qt::Key_F, Qt::ControlModifier | Qt::ShiftModifier, s));
    }
};

QTEST_GUILESS_MAIN(TestVrHelpers)
#include "testvrhelpers.moc"
