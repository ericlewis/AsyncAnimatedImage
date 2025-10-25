import SwiftUI

protocol GIFAnimatableDelegate: AnyObject {
    func update(url: URL, imageHash: Int) async
}

class GIFAnimationContainer: _GIFAnimatable {
    
    // MARK: Properties
    var image: UIImage?
    
    lazy var animator: _Animator = _Animator(withDelegate: self)
    
    var url: URL
    var size: CGSize
    var task: Task<Void, Never>?
    weak var delegate: GIFAnimatableDelegate!
    
    // MARK: Initializer
    init(url: URL, size: CGSize, delegate: GIFAnimatableDelegate) {
        self.url = url
        self.delegate = delegate
        self.size = size
        animate(withGIFURL: url)
    }
    
    func animatorHasNewFrame() {
        guard let frame = animator.activeFrame() else { return }
        self.image = frame
        Task {
            await self.delegate.update(url: self.url, imageHash: frame.hashValue)
        }
    }
    
    // MARK: Animation
    func animate(withGIFURL imageURL: URL, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        self.task?.cancel()
        self.task = Task {
            do {
                let image: UIImage?
                let data: Data
                if let storedImage = AnimatedImageCache.shared.getImage(for: imageURL) {
                    image = storedImage.image
                    data = storedImage.data
                } else {
                    let (receivedData, _) = try await URLSession.shared.data(from: imageURL)
                    try Task.checkCancellation()
                    image = size == .zero ? UIImage(data: receivedData) : UIImage(data: receivedData)?.resized(to: size)
                    data = receivedData

                    AnimatedImageCache.shared.set(image: image, data: data, for: imageURL)
                }

                self.image = image
                await self.delegate.update(url: imageURL, imageHash: image?.hashValue ?? 0)
                self.animator.animate(withGIFData: data, size: size, contentMode: .center, loopCount: loopCount, preparationBlock: preparationBlock, animationBlock: animationBlock, loopBlock: loopBlock)
            } catch {
                // Consider a better error handling mechanism here, e.g., delegate method.
                print("Error downloading gif:", error.localizedDescription, "at url:", imageURL.absoluteString)
            }
        }
    }
    
    deinit {
        self.task?.cancel()
    }
}

class RetainedAnimationContainer {
    let container: GIFAnimationContainer
    public var refCount: Int

    internal init(container: GIFAnimationContainer) {
        self.container = container
        self.refCount = 0
    }
}

class ImageContainer {
    let image: UIImage
    let data: Data

    internal init(image: UIImage, data: Data) {
        self.image = image
        self.data = data
    }
}

@Observable public class AnimatedImageCache: GIFAnimatableDelegate {
    public static let shared = AnimatedImageCache()

    private var timer: Timer?

    private var containers: [URL: RetainedAnimationContainer] = [:]
    private var images: NSCache<NSURL, ImageContainer> = .init()

    /// URL hash to image hash
    var imageHashes: [Int: Int] = [:]

    public init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            // We use a reoccuring timer to clean up groups of images that aren't being referenced
            // This prevents issues with registering images in render right after we dereference a container
            for (url, container) in self.containers {
                if container.refCount <= 0 {
                    // Destroy container
                    self.containers.removeValue(forKey: url)
                }
            }
        }
    }

    private func register(url: URL?, size: CGSize) -> UIImage? {
        guard let url else { return nil }

        var cachedContainer = containers[url]

        if cachedContainer == nil {
            let container = RetainedAnimationContainer(container: GIFAnimationContainer(url: url, size: size, delegate: self))
            containers[url] = container
            cachedContainer = container
        }

        // Indicate to SwiftUI that it should rerender due to the observable (the dictionary) changing
        let _ = imageHashes[url.hashValue]
        return cachedContainer?.container.image
    }

    public func gifImage(for url: URL?, size: CGSize = .zero) -> Image? {
        guard let image = register(url: url, size: size) else {
            return nil
        }

        return Image(uiImage: image)
    }

    public func onAppear(for url: URL) {
        guard let container = containers[url] else {
            print("Attempted to increment refcount image at URL \(url), but image has not been registered")
            return
        }

        container.refCount += 1
    }

    public func onAppear(for urls: [URL]) {
        for url in urls {
            onAppear(for: url)
        }
    }

    public func onDisappear(for url: URL) {
        guard let container = containers[url] else {
            print("Attempted to decrement refcount image at URL \(url), but image has not been registered")
            return
        }

        // We will destroy the container via a periodic task
        container.refCount -= 1

        if container.refCount < 0 {
            container.refCount = 0
        }
    }

    public func onDisappear(for urls: [URL]) {
        for url in urls {
            onDisappear(for: url)
        }
    }

    public func flush() {
        containers.removeAll()
    }

    @MainActor
    internal func update(url: URL, imageHash: Int) {
        imageHashes[url.hashValue] = imageHash
    }

    internal func set(image: UIImage?, data: Data, for url: URL) {
        guard let image = image else {
            images.removeObject(forKey: url as NSURL)
            return
        }

        images.setObject(ImageContainer(image: image, data: data), forKey: url as NSURL)
    }

    internal func getImage(for url: URL) -> ImageContainer? {
        images.object(forKey: url as NSURL)
    }
}

public func AsyncAnimatedImage(url: URL?, size: CGSize = .zero) -> Image? {
    AnimatedImageCache.shared.gifImage(for: url, size: size)
}
