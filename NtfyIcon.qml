import QtQuick
import QtQuick.Shapes
import qs.Commons

// Official ntfy mark: speech bubble with a terminal prompt `<_`.
// Path is the public ntfy icon (simple-icons / ntfy Apache-2.0 assets),
// drawn in QML so it follows the bar foreground instead of a bitmap.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool muted: false

  // Mute slash. All values are fractions of iconSize.
  // The slash is a rounded Rectangle, rotated -45°, drawn on top of the
  // bubble — it is not part of the SVG path. Tweak these, save, then look
  // at the muted header icon (click the mark to mute). If the bar keeps
  // the old stroke, run: omarchy restart shell
  property real slashLength: 1.42      // how long the stroke is
  property real slashThickness: 0.12   // how thick the stroke is
  property real slashNudge: 0.10       // shift toward the upper-right

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real markScale: iconSize / 24

  Shape {
    id: mark
    width: 24
    height: 24
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 4
    transform: Scale {
      origin.x: 0
      origin.y: 0
      xScale: root.markScale
      yScale: root.markScale
    }

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      fillRule: ShapePath.OddEvenFill
      PathSvg {
        path: "M12.597 13.693v2.156h6.205v-2.156ZM5.183 6.549v2.363l3.591 1.901.023.01-.023.009-3.591 1.901v2.35l.386-.211 5.456-2.969V9.729ZM3.659 2.037C1.915 2.037.42 3.41.42 5.154v.002L.438 18.73 0 21.963l5.956-1.583h14.806c1.744 0 3.238-1.374 3.238-3.118V5.154c0-1.744-1.493-3.116-3.237-3.117h-.001zm0 2.2h17.104c.613.001 1.037.447 1.037.917v12.108c0 .47-.424.916-1.038.916H5.633l-3.026.915.031-.179-.017-13.76c0-.47.424-.917 1.038-.917z"
      }
    }
  }

  Rectangle {
    visible: root.muted
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: parent.width * root.slashNudge
    anchors.verticalCenterOffset: -parent.height * root.slashNudge
    width: parent.width * root.slashLength
    height: Math.max(2, parent.height * root.slashThickness)
    radius: height / 2
    color: root.color
    rotation: -45
  }
}
