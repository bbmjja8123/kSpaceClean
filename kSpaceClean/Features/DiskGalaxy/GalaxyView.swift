import SwiftUI
import SceneKit
import DesignSystem

struct GalaxyView: NSViewRepresentable {
    @ObservedObject var viewModel: GalaxyViewModel

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.delegate = context.coordinator

        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)

        let doubleClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClickGesture.numberOfClicksRequired = 2
        scnView.addGestureRecognizer(doubleClickGesture)

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.updateScene(with: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        let sceneBuilder = GalaxyScene()
        var scene: SCNScene
        var viewModel: GalaxyViewModel

        init(viewModel: GalaxyViewModel) {
            self.viewModel = viewModel
            self.scene = sceneBuilder.scene
            super.init()
            setupScene()
        }

        private func setupScene() {
            sceneBuilder.addCamera()
            sceneBuilder.addLighting()
            sceneBuilder.addParticleStars()
        }

        @MainActor func updateScene(with viewModel: GalaxyViewModel) {
            // Remove previous galaxy container and all spheres
            scene.rootNode.childNodes.filter { $0.name == "galaxyContainer" || $0.geometry is SCNSphere }.forEach { $0.removeFromParentNode() }

            guard !viewModel.categories.isEmpty else { return }

            let sphereNodes = viewModel.categories.map { sceneBuilder.buildSphere(for: $0.category, size: $0.totalSize) }
            let container = sceneBuilder.arrangeSpheres(sphereNodes)
            container.name = "galaxyContainer"
            scene.rootNode.addChildNode(container)
        }

        @MainActor @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.categoryBitMask: 1])

            if let hit = hits.first, let categoryName = hit.node.name {
                viewModel.selectCategory(categoryName)
            } else {
                viewModel.deselectAll()
            }
        }

        @MainActor @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.categoryBitMask: 1])

            if let hit = hits.first, let categoryName = hit.node.name {
                viewModel.drillDown(categoryName)
            } else {
                viewModel.deselectAll()
            }
        }
    }
}
