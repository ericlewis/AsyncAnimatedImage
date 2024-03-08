import SwiftUI
import Gifu
import MobileCoreServices

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
    var delegate: GIFAnimatableDelegate

    init(url: URL, delegate: GIFAnimatableDelegate) {
        self.url = url
        self.delegate = delegate
        (layer as! CallbackLayer).onDisplay = { [weak self] in
            self?.updateImageIfNeeded()
            delegate.update(url: url, image: self?.image ?? UIImage())
        }
        self.animate(withGIFURL: url)
    }

    // Replicates GIFAnimatable.animate(withGIFURL, ...)
    func animate(withGIFURL imageURL: URL, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        let session = URLSession.shared

        let task = session.dataTask(with: imageURL) { (data, response, error) in
            switch (data, response, error) {
            case (.none, _, let error?):
                print("Error downloading gif:", error.localizedDescription, "at url:", imageURL.absoluteString)
            case (let data?, _, _):
                DispatchQueue.main.async {
                    guard self.isAnimatedGif(data: data) else {
                        self.delegate.update(url: imageURL, image: UIImage(data: data) ?? UIImage())
                        return
                    }

                    self.animate(withGIFData: data, loopCount: loopCount, preparationBlock: preparationBlock, animationBlock: animationBlock, loopBlock: loopBlock)
                }
            default: ()
            }
        }

        task.resume()
    }

    func isAnimatedGif(data: Data) -> Bool {
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
            let isTypeGIF = UTTypeConformsTo(CGImageSourceGetType(imageSource) ?? "" as CFString, kUTTypeGIF)
            let imageCount = CGImageSourceGetCount(imageSource)

            return isTypeGIF && imageCount > 1
        } else {
            return false
        }
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
