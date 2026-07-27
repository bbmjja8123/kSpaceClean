import SceneKit
import DesignSystem

#if canImport(AppKit)
import AppKit
#endif

public final class GalaxyScene {
    public let scene = SCNScene()
    private var spheres: [SCNNode] = []

    public func buildSphere(for category: FileCategory, size: Double) -> SCNNode {
        let radius = 0.5 + log2(size + 1) * 0.3
        let clampedRadius = min(max(radius, 0.5), 3.0)

        let sphere = SCNSphere(radius: CGFloat(clampedRadius))
        // Safe NSColor extraction via cgColor (NSColor(SwiftUI.Color) bridging can crash)
        let cgColor = category.color.cgColor ?? CGColor(gray: 0.5, alpha: 1)
        sphere.firstMaterial?.diffuse.contents = cgColor.copy(alpha: 0.85) ?? cgColor
        sphere.firstMaterial?.specular.contents = CGColor(gray: 1, alpha: 0.3)
        sphere.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: sphere)
        node.categoryBitMask = 1
        node.name = category.rawValue

        // Subtle floating animation
        let floatUp = CABasicAnimation(keyPath: "position.y")
        floatUp.fromValue = node.position.y - 0.2
        floatUp.toValue = node.position.y + 0.2
        floatUp.autoreverses = true
        floatUp.repeatCount = .infinity
        floatUp.duration = 2.0 + Double.random(in: 0...1)
        floatUp.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(floatUp, forKey: "float")

        return node
    }

    public func arrangeSpheres(_ spheres: [SCNNode]) -> SCNNode {
        let container = SCNNode()
        let count = spheres.count
        for (index, node) in spheres.enumerated() {
            let angle = Double(index) / Double(count) * .pi * 2
            let radius: Float = 5.0
            node.position = SCNVector3(
                cos(Float(angle)) * radius,
                sin(Float(angle)) * radius * 0.6,
                -Float(index) * 0.5
            )
            container.addChildNode(node)
        }

        // Slow galaxy rotation
        let rotate = CABasicAnimation(keyPath: "rotation")
        rotate.fromValue = SCNVector4(0, 1, 0, 0)
        rotate.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
        rotate.duration = 30
        rotate.repeatCount = .infinity
        container.addAnimation(rotate, forKey: "galaxyRotation")

        return container
    }

    public func addCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 100

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 15)
        scene.rootNode.addChildNode(cameraNode)
    }

    public func addLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 300
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 800
        directional.position = SCNVector3(5, 10, 10)
        scene.rootNode.addChildNode(directional)
    }

    public func addParticleStars() {
        let particle = SCNParticleSystem()
        particle.birthRate = 50
        particle.loops = true
        particle.emissionDuration = 1
        particle.particleLifeSpan = 10
        particle.particleSize = 0.05
        particle.spreadingAngle = 180
        particle.emitterShape = SCNSphere(radius: 30)
        let particleNode = SCNNode()
        particleNode.addParticleSystem(particle)
        scene.rootNode.addChildNode(particleNode)
    }
}
