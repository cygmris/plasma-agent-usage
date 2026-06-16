/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Circular progress ring (extracted from baseline drawCircularProgress).
    Pure presentation: feed `percent` (0..100) and `progressColor`.
*/

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: ring

    property real percent: 0
    property color progressColor: Kirigami.Theme.positiveTextColor
    property int lineWidth: 3

    Canvas {
        id: canvas
        anchors.fill: parent

        property real _percent: ring.percent
        property color _color: ring.progressColor
        on_PercentChanged: requestPaint()
        on_ColorChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            var centerX = w / 2
            var centerY = h / 2
            var radius = Math.min(w, h) / 2 - 2
            var startAngle = -Math.PI / 2
            var pct = Math.min(ring.percent, 100)
            var endAngle = startAngle + (2 * Math.PI * pct / 100)

            ctx.reset()

            // Background circle
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
            ctx.strokeStyle = Kirigami.Theme.disabledTextColor
            ctx.globalAlpha = 0.3
            ctx.lineWidth = ring.lineWidth
            ctx.stroke()

            // Progress arc
            if (ring.percent > 0) {
                ctx.beginPath()
                ctx.arc(centerX, centerY, radius, startAngle, endAngle)
                ctx.strokeStyle = ring.progressColor
                ctx.globalAlpha = 1.0
                ctx.lineWidth = ring.lineWidth
                ctx.lineCap = "round"
                ctx.stroke()
            }
        }
    }
}
