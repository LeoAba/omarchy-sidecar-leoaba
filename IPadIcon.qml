import QtQuick
import QtQuick.Shapes

// A classic iPad standing upright: rounded body, screen cut out, home button.
// Drawn as a single even-odd path so it scales cleanly at any size.
Item {
  id: root

  property real iconSize: 16
  property color color: "white"

  implicitWidth: iconSize
  implicitHeight: iconSize

  // Ink box in artboard units: x, y, width, height.
  readonly property var ink: [4, 1.5, 16, 21]
  readonly property real fit: iconSize / Math.max(ink[2], ink[3])

  Shape {
    width: 24
    height: 24
    transform: [
      Translate { x: -root.ink[0]; y: -root.ink[1] },
      Scale { xScale: root.fit; yScale: root.fit },
      Translate {
        x: (root.iconSize - root.ink[2] * root.fit) / 2
        y: (root.iconSize - root.ink[3] * root.fit) / 2
      }
    ]
    preferredRendererType: Shape.CurveRenderer
    // Rendered at 3x and sampled down so the thin bezels stay crisp at bar size.
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(width * root.fit * 3, height * root.fit * 3)

    ShapePath {
      fillColor: root.color
      strokeWidth: -1
      fillRule: ShapePath.OddEvenFill
      PathSvg {
        path: "M7 1.5H17A3 3 0 0 1 20 4.5V19.5A3 3 0 0 1 17 22.5H7A3 3 0 0 1 4 19.5V4.5A3 3 0 0 1 7 1.5Z"
            + "M6.6 3.6H17.4A1 1 0 0 1 18.4 4.6V17.9A1 1 0 0 1 17.4 18.9H6.6A1 1 0 0 1 5.6 17.9V4.6A1 1 0 0 1 6.6 3.6Z"
            + "M12 19.75A0.95 0.95 0 1 0 12 21.65A0.95 0.95 0 1 0 12 19.75Z"
      }
    }
  }
}
