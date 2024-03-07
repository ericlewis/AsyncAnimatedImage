import SwiftUI
import Gifu

protocol GIFAnimatableDelegate {
    func update(url: URL, image: UIImage)
}

class CallbackLayer: CALayer {
    
    var onDisplay: () -> Void = {}
    
    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        onDisplay()
    }
}

class GIFAnimationContainer: GIFAnimatable, ImageContainer {
    var image: UIImage?
    
    lazy var animator: Animator? = Animator(withDelegate: self)
    
    var layer: CALayer = CallbackLayer()
    var frame: CGRect = .zero
    var contentMode: UIView.ContentMode = .scaleAspectFit
    
    var url: URL
    
    init(url: URL, delegate: GIFAnimatableDelegate) {
        self.url = url
        (layer as! CallbackLayer).onDisplay = { [weak self] in
            self?.updateImageIfNeeded()
            delegate.update(url: url, image: self?.image ?? UIImage())
        }
        animate(withGIFURL: url)
    }
}

@Observable class AnimatedImageCache: GIFAnimatableDelegate, ObservableObject {
    
    static let shared = AnimatedImageCache()
    
    private var containers: [URL: GIFAnimationContainer] = [:]
    private(set) var images: [URL: UIImage] = [:]

    func register(url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let image = images[url] {
            return image
        }
        if containers[url] == nil {
            containers[url] = GIFAnimationContainer(url: url, delegate: self)
        }
        return images[url]
    }
    
    func gifImage(for url: URL?) -> Image {
        Image(uiImage: register(url: url) ?? UIImage())
    }
    
    func update(url: URL, image: UIImage) {
        images[url] = image
    }
}

public func AsyncAnimatedImage(url: URL?) -> Image {
    AnimatedImageCache.shared.gifImage(for: url)
}
