//The MIT License (MIT)
//
//Copyright (c) 2014-2018 Reda Lemeden.
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of
//this software and associated documentation files (the "Software"), to deal in
//the Software without restriction, including without limitation the rights to
//use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//the Software, and to permit persons to whom the Software is furnished to do so,
//subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//The name and characters used in the demo of this software are property of their
//respective owners.

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

public protocol _GIFAnimatable: AnyObject {
    func animatorHasNewFrame()
}

/// Represents a single frame in a GIF.
struct _AnimatedFrame {
    
    /// The image to display for this frame. Its value is nil when the frame is removed from the buffer.
    let image: UIImage?
    
    /// The duration that this frame should remain active.
    let duration: TimeInterval
    
    /// A placeholder frame with no image assigned.
    /// Used to replace frames that are no longer needed in the animation.
    var placeholderFrame: _AnimatedFrame {
        return _AnimatedFrame(image: nil, duration: duration)
    }
    
    /// Whether this frame instance contains an image or not.
    var isPlaceholder: Bool {
        return image == nil
    }
    
    /// Returns a new instance from an optional image.
    ///
    /// - parameter image: An optional `UIImage` instance to be assigned to the new frame.
    /// - returns: An `AnimatedFrame` instance.
    func makeAnimatedFrame(with newImage: UIImage?) -> _AnimatedFrame {
        return _AnimatedFrame(image: newImage, duration: duration)
    }
}

public class _Animator {
    
    /// Total duration of one animation loop
    var loopDuration: TimeInterval {
        return frameStore?.loopDuration ?? 0
    }
    
    /// Number of frame to buffer.
    var frameBufferCount = 50
    
    /// Specifies whether GIF frames should be resized.
    var shouldResizeFrames = true
    
    /// Responsible for loading individual frames and resizing them if necessary.
    var frameStore: _FrameStore?
    
    /// Tracks whether the display link is initialized.
    private var displayLinkInitialized: Bool = false
    
    /// A delegate responsible for displaying the GIF frames.
    private weak var delegate: _GIFAnimatable!
    
    /// Callback for when all the loops of the animation are done (never called for infinite loops)
    private var animationBlock: (() -> Void)? = nil
    
    /// Callback for when a loop is done (at the end of each loop)
    private var loopBlock: (() -> Void)? = nil
    
    /// Responsible for starting and stopping the animation.
    private lazy var displayLink: CADisplayLink = { [unowned self] in
        self.displayLinkInitialized = true
        let display = CADisplayLink(target: DisplayLinkProxy(target: self), selector: #selector(DisplayLinkProxy.onScreenUpdate))
        display.isPaused = true
        return display
    }()
    
    /// Introspect whether the `displayLink` is paused.
    var isAnimating: Bool {
        return !displayLink.isPaused
    }
    
    /// Total frame count of the GIF.
    var frameCount: Int {
        return frameStore?.frameCount ?? 0
    }
    
    /// Creates a new animator with a delegate.
    ///
    /// - parameter view: A view object that implements the `GIFAnimatable` protocol.
    ///
    /// - returns: A new animator instance.
    public init(withDelegate delegate: _GIFAnimatable) {
        self.delegate = delegate
    }
    
    /// Checks if there is a new frame to display.
    fileprivate func updateFrameIfNeeded() {
        guard let store = frameStore else { return }
        if store.isFinished {
            stopAnimating()
            if let animationBlock = animationBlock {
                animationBlock()
            }
            return
        }
        
        store.shouldChangeFrame(with: displayLink.duration) {
            if $0 {
                delegate.animatorHasNewFrame()
                if store.isLoopFinished, let loopBlock = loopBlock {
                    loopBlock()
                }
            }
        }
    }
    
    /// Prepares the animator instance for animation.
    ///
    /// - parameter imageName: The file name of the GIF in the specified bundle.
    /// - parameter bundle: The bundle where the GIF is located (default Bundle.main).
    /// - parameter size: The target size of the individual frames.
    /// - parameter contentMode: The view content mode to use for the individual frames.
    /// - parameter loopCount: Desired number of loops, <= 0 for infinite loop.
    /// - parameter completionHandler: Completion callback function
    func prepareForAnimation(withGIFNamed imageName: String, inBundle bundle: Bundle = .main, size: CGSize, contentMode: UIView.ContentMode, loopCount: Int = 0, completionHandler: (() -> Void)? = nil) {
        guard let extensionRemoved = imageName.components(separatedBy: ".")[safe: 0],
              let imagePath = bundle.url(forResource: extensionRemoved, withExtension: "gif"),
              let data = try? Data(contentsOf: imagePath) else { return }
        
        prepareForAnimation(withGIFData: data,
                            size: size,
                            contentMode: contentMode,
                            loopCount: loopCount,
                            completionHandler: completionHandler)
    }
    
    /// Prepares the animator instance for animation.
    ///
    /// - parameter imageData: GIF image data.
    /// - parameter size: The target size of the individual frames.
    /// - parameter contentMode: The view content mode to use for the individual frames.
    /// - parameter loopCount: Desired number of loops, <= 0 for infinite loop.
    /// - parameter completionHandler: Completion callback function
    func prepareForAnimation(withGIFData imageData: Data, size: CGSize, contentMode: UIView.ContentMode, loopCount: Int = 0, completionHandler: (() -> Void)? = nil) {
        frameStore = _FrameStore(data: imageData,
                                 size: size,
                                 contentMode: contentMode,
                                 framePreloadCount: frameBufferCount,
                                 loopCount: loopCount)
        frameStore!.shouldResizeFrames = shouldResizeFrames
        frameStore!.prepareFrames(completionHandler)
        attachDisplayLink()
    }
    
    /// Add the display link to the main run loop.
    private func attachDisplayLink() {
        displayLink.add(to: .main, forMode: RunLoop.Mode.common)
    }
    
    deinit {
        if displayLinkInitialized {
            displayLink.invalidate()
        }
    }
    
    /// Start animating.
    func startAnimating() {
        if frameStore?.isAnimatable ?? false {
            displayLink.isPaused = false
        }
    }
    
    /// Stop animating.
    func stopAnimating() {
        displayLink.isPaused = true
    }
    
    /// Prepare for animation and start animating immediately.
    ///
    /// - parameter imageName: The file name of the GIF in the main bundle.
    /// - parameter size: The target size of the individual frames.
    /// - parameter contentMode: The view content mode to use for the individual frames.
    /// - parameter loopCount: Desired number of loops, <= 0 for infinite loop.
    /// - parameter preparationBlock: Callback for when preparation is done
    /// - parameter animationBlock: Callback for when all the loops of the animation are done (never called for infinite loops)
    /// - parameter loopBlock: Callback for when a loop is done (at the end of each loop)
    func animate(withGIFNamed imageName: String, size: CGSize, contentMode: UIView.ContentMode, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        self.animationBlock = animationBlock
        self.loopBlock = loopBlock
        prepareForAnimation(withGIFNamed: imageName,
                            size: size,
                            contentMode: contentMode,
                            loopCount: loopCount,
                            completionHandler: preparationBlock)
        startAnimating()
    }
    
    /// Prepare for animation and start animating immediately.
    ///
    /// - parameter imageData: GIF image data.
    /// - parameter size: The target size of the individual frames.
    /// - parameter contentMode: The view content mode to use for the individual frames.
    /// - parameter loopCount: Desired number of loops, <= 0 for infinite loop.
    /// - parameter preparationBlock: Callback for when preparation is done
    /// - parameter animationBlock: Callback for when all the loops of the animation are done (never called for infinite loops)
    /// - parameter loopBlock: Callback for when a loop is done (at the end of each loop)
    func animate(withGIFData imageData: Data, size: CGSize, contentMode: UIView.ContentMode, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil)  {
        self.animationBlock = animationBlock
        self.loopBlock = loopBlock
        prepareForAnimation(withGIFData: imageData,
                            size: size,
                            contentMode: contentMode,
                            loopCount: loopCount,
                            completionHandler: preparationBlock)
        startAnimating()
    }
    
    /// Stop animating and nullify the frame store.
    func prepareForReuse() {
        stopAnimating()
        frameStore = nil
    }
    
    /// Gets the current image from the frame store.
    ///
    /// - returns: An optional frame image to display.
    func activeFrame() -> UIImage? {
        return frameStore?.currentFrameImage
    }
}

/// A proxy class to avoid a retain cycle with the display link.
fileprivate class DisplayLinkProxy {
    
    /// The target animator.
    private weak var target: _Animator?
    
    /// Create a new proxy object with a target animator.
    ///
    /// - parameter target: An animator instance.
    ///
    /// - returns: A new proxy instance.
    init(target: _Animator) { self.target = target }
    
    /// Lets the target update the frame if needed.
    @objc func onScreenUpdate() { target?.updateFrameIfNeeded() }
}

class _FrameStore {
    
    /// Total duration of one animation loop
    var loopDuration: TimeInterval = 0
    
    /// Flag indicating that a single loop has finished
    var isLoopFinished: Bool = false
    
    /// Flag indicating if number of loops has been reached (never true for infinite loop)
    var isFinished: Bool = false
    
    /// Desired number of loops, <= 0 for infinite loop
    let loopCount: Int
    
    /// Index of current loop
    var currentLoop = 0
    
    /// Maximum duration to increment the frame timer with.
    let maxTimeStep = 1.0
    
    /// An array of animated frames from a single GIF image.
    var animatedFrames = [_AnimatedFrame]()
    
    /// The target size for all frames.
    let size: CGSize
    
    /// The content mode to use when resizing.
    let contentMode: UIView.ContentMode
    
    /// Maximum number of frames to load at once
    let bufferFrameCount: Int
    
    /// The total number of frames in the GIF.
    var frameCount = 0
    
    /// A reference to the original image source.
    var imageSource: CGImageSource
    
    /// The index of the current GIF frame.
    var currentFrameIndex = 0 {
        didSet {
            previousFrameIndex = oldValue
        }
    }
    
    /// The index of the previous GIF frame.
    var previousFrameIndex = 0 {
        didSet {
            preloadFrameQueue.async {
                self.updatePreloadedFrames()
            }
        }
    }
    
    /// Time elapsed since the last frame change. Used to determine when the frame should be updated.
    var timeSinceLastFrameChange: TimeInterval = 0.0
    
    /// Specifies whether GIF frames should be resized.
    var shouldResizeFrames = true
    
    /// Dispatch queue used for preloading images.
    private lazy var preloadFrameQueue: DispatchQueue = {
        return DispatchQueue(label: "co.kaishin.Gifu.preloadQueue")
    }()
    
    /// The current image frame to show.
    var currentFrameImage: UIImage? {
        return frame(at: currentFrameIndex)
    }
    
    /// The current frame duration
    var currentFrameDuration: TimeInterval {
        return duration(at: currentFrameIndex)
    }
    
    /// Is this image animatable?
    var isAnimatable: Bool {
        return imageSource.isAnimatedGIF
    }
    
    private let lock = NSLock()
    
    /// Creates an animator instance from raw GIF image data and an `Animatable` delegate.
    ///
    /// - parameter data: The raw GIF image data.
    /// - parameter delegate: An `Animatable` delegate.
    init(data: Data, size: CGSize, contentMode: UIView.ContentMode, framePreloadCount: Int, loopCount: Int) {
        let options = [String(kCGImageSourceShouldCache): kCFBooleanFalse] as CFDictionary
        self.imageSource = CGImageSourceCreateWithData(data as CFData, options) ?? CGImageSourceCreateIncremental(options)
        self.size = size
        self.contentMode = contentMode
        self.bufferFrameCount = framePreloadCount
        self.loopCount = loopCount
    }
    
    // MARK: - Frames
    /// Loads the frames from an image source, resizes them, then caches them in `animatedFrames`.
    func prepareFrames(_ completionHandler: (() -> Void)? = nil) {
        frameCount = Int(CGImageSourceGetCount(imageSource))
        lock.lock()
        animatedFrames.reserveCapacity(frameCount)
        lock.unlock()
        preloadFrameQueue.async {
            self.setupAnimatedFrames()
            completionHandler?()
        }
    }
    
    /// Returns the frame at a particular index.
    ///
    /// - parameter index: The index of the frame.
    /// - returns: An optional image at a given frame.
    func frame(at index: Int) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return animatedFrames[safe: index]?.image
    }
    
    /// Returns the duration at a particular index.
    ///
    /// - parameter index: The index of the duration.
    /// - returns: The duration of the given frame.
    func duration(at index: Int) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return animatedFrames[safe: index]?.duration ?? TimeInterval.infinity
    }
    
    /// Checks whether the frame should be changed and calls a handler with the results.
    ///
    /// - parameter duration: A `CFTimeInterval` value that will be used to determine whether frame should be changed.
    /// - parameter handler: A function that takes a `Bool` and returns nothing. It will be called with the frame change result.
    func shouldChangeFrame(with duration: CFTimeInterval, handler: (Bool) -> Void) {
        incrementTimeSinceLastFrameChange(with: duration)
        
        if currentFrameDuration > timeSinceLastFrameChange {
            handler(false)
        } else {
            resetTimeSinceLastFrameChange()
            incrementCurrentFrameIndex()
            handler(true)
        }
    }
}

private extension _FrameStore {
    /// Whether preloading is needed or not.
    var preloadingIsNeeded: Bool {
        return bufferFrameCount < frameCount - 1
    }
    
    /// Optionally loads a single frame from an image source, resizes it if required, then returns an `UIImage`.
    ///
    /// - parameter index: The index of the frame to load.
    /// - returns: An optional `UIImage` instance.
    func loadFrame(at index: Int) -> UIImage? {
        guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else { return nil }
        let image = UIImage(cgImage: imageRef)
        let scaledImage: UIImage?
        
        if shouldResizeFrames {
            switch self.contentMode {
            case .scaleAspectFit: scaledImage = image.constrained(by: size)
            case .scaleAspectFill: scaledImage = image.filling(size: size)
            default: scaledImage = size != .zero ? image.resized(to: size) : nil
            }
        } else {
            scaledImage = image
        }
        
        return scaledImage
    }
    
    /// Updates the frames by preloading new ones and replacing the previous frame with a placeholder.
    func updatePreloadedFrames() {
        if !preloadingIsNeeded { return }
        lock.lock()
        animatedFrames[previousFrameIndex] = animatedFrames[previousFrameIndex].placeholderFrame
        lock.unlock()
        
        for index in preloadIndexes(withStartingIndex: currentFrameIndex) {
            loadFrameAtIndexIfNeeded(index)
        }
    }
    
    func loadFrameAtIndexIfNeeded(_ index: Int) {
        let frame: _AnimatedFrame
        lock.lock()
        frame = animatedFrames[index]
        lock.unlock()
        if !frame.isPlaceholder { return }
        let loadedFrame = frame.makeAnimatedFrame(with: loadFrame(at: index))
        lock.lock()
        animatedFrames[index] = loadedFrame
        lock.unlock()
    }
    
    /// Increments the `timeSinceLastFrameChange` property with a given duration.
    ///
    /// - parameter duration: An `NSTimeInterval` value to increment the `timeSinceLastFrameChange` property with.
    func incrementTimeSinceLastFrameChange(with duration: TimeInterval) {
        timeSinceLastFrameChange += min(maxTimeStep, duration)
    }
    
    /// Ensures that `timeSinceLastFrameChange` remains accurate after each frame change by substracting the `currentFrameDuration`.
    func resetTimeSinceLastFrameChange() {
        timeSinceLastFrameChange -= currentFrameDuration
    }
    
    /// Increments the `currentFrameIndex` property.
    func incrementCurrentFrameIndex() {
        currentFrameIndex = increment(frameIndex: currentFrameIndex)
        if isLastFrame(frameIndex: currentFrameIndex) {
            isLoopFinished = true
            if isLastLoop(loopIndex: currentLoop) {
                isFinished = true
            }
        } else {
            isLoopFinished = false
            if currentFrameIndex == 0 {
                currentLoop = currentLoop + 1
            }
        }
    }
    
    /// Increments a given frame index, taking into account the `frameCount` and looping when necessary.
    ///
    /// - parameter index: The `Int` value to increment.
    /// - parameter byValue: The `Int` value to increment with.
    /// - returns: A new `Int` value.
    func increment(frameIndex: Int, by value: Int = 1) -> Int {
        return (frameIndex + value) % frameCount
    }
    
    /// Indicates if current frame is the last one.
    /// - parameter frameIndex: Index of current frame.
    /// - returns: True if current frame is the last one.
    func isLastFrame(frameIndex: Int) -> Bool {
        return frameIndex == frameCount - 1
    }
    
    /// Indicates if current loop is the last one. Always false for infinite loops.
    /// - parameter loopIndex: Index of current loop.
    /// - returns: True if current loop is the last one.
    func isLastLoop(loopIndex: Int) -> Bool {
        return loopIndex == loopCount - 1
    }
    
    /// Returns the indexes of the frames to preload based on a starting frame index.
    ///
    /// - parameter index: Starting index.
    /// - returns: An array of indexes to preload.
    func preloadIndexes(withStartingIndex index: Int) -> [Int] {
        let nextIndex = increment(frameIndex: index)
        let lastIndex = increment(frameIndex: index, by: bufferFrameCount)
        
        if lastIndex >= nextIndex {
            return [Int](nextIndex...lastIndex)
        } else {
            return [Int](nextIndex..<frameCount) + [Int](0...lastIndex)
        }
    }
    
    func setupAnimatedFrames() {
        resetAnimatedFrames()
        
        var duration: TimeInterval = 0
        
        (0..<frameCount).forEach { index in
            lock.lock()
            let frameDuration = CGImageFrameDuration(with: imageSource, atIndex: index)
            duration += min(frameDuration, maxTimeStep)
            animatedFrames += [_AnimatedFrame(image: nil, duration: frameDuration)]
            lock.unlock()
            
            if index > bufferFrameCount { return }
            loadFrameAtIndexIfNeeded(index)
        }
        
        self.loopDuration = duration
    }
    
    /// Reset animated frames.
    func resetAnimatedFrames() {
        animatedFrames = []
    }
}


typealias GIFProperties = [String: Double]

/// Most GIFs run between 15 and 24 Frames per second.
///
/// If a GIF does not have (frame-)durations stored in its metadata,
/// this default framerate is used to calculate the GIFs duration.
private let defaultFrameRate: Double = 15.0

/// Default Fallback Frame-Duration based on `defaultFrameRate`
private let defaultFrameDuration: Double = 1 / defaultFrameRate

/// Threshold used in `capDuration` for a FrameDuration
private let capDurationThreshold: Double = 0.02 - Double.ulpOfOne

/// Frameduration used, if a frame-duration is below `capDurationThreshold`
private let minFrameDuration: Double = 0.1

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices ~= index ? self[index] : nil
    }
}

/// Retruns the duration of a frame at a specific index using an image source (an `CGImageSource` instance).
///
/// - returns: A frame duration.
func CGImageFrameDuration(with imageSource: CGImageSource, atIndex index: Int) -> TimeInterval {
    guard imageSource.isAnimatedGIF else { return 0.0 }
    
    // Return nil, if the properties do not store a FrameDuration or FrameDuration <= 0
    guard let GIFProperties = imageSource.properties(at: index),
          let duration = frameDuration(with: GIFProperties),
          duration > 0 else { return defaultFrameDuration }
    
    return capDuration(with: duration)
}

/// Ensures that a duration is never smaller than a threshold value.
///
/// - returns: A capped frame duration.
func capDuration(with duration: Double) -> Double {
    let cappedDuration = duration < capDurationThreshold ? 0.1 : duration
    return cappedDuration
}

/// Returns a frame duration from a `GIFProperties` dictionary.
///
/// - returns: A frame duration.
func frameDuration(with properties: GIFProperties) -> Double? {
    guard let unclampedDelayTime = properties[String(kCGImagePropertyGIFUnclampedDelayTime)],
          let delayTime = properties[String(kCGImagePropertyGIFDelayTime)]
    else { return nil }
    
    return duration(withUnclampedTime: unclampedDelayTime, andClampedTime: delayTime)
}

/// Calculates frame duration based on both clamped and unclamped times.
///
/// - returns: A frame duration.
func duration(withUnclampedTime unclampedDelayTime: Double, andClampedTime delayTime: Double) -> Double? {
    let delayArray = [unclampedDelayTime, delayTime]
    return delayArray.filter({ $0 >= 0 }).first
}

/// An extension of `CGImageSourceRef` that adds GIF introspection and easier property retrieval.
extension CGImageSource {
    /// Returns whether the image source contains an animated GIF.
    ///
    /// - returns: A boolean value that is `true` if the image source contains animated GIF data.
    var isAnimatedGIF: Bool {
        let isTypeGIF = CGImageSourceGetType(self) == UTType.gif.identifier as CFString
        let imageCount = CGImageSourceGetCount(self)
        return isTypeGIF != false && imageCount > 1
    }
    
    /// Returns the GIF properties at a specific index.
    ///
    /// - parameter index: The index of the GIF properties to retrieve.
    /// - returns: A dictionary containing the GIF properties at the passed in index.
    func properties(at index: Int) -> GIFProperties? {
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [String: AnyObject] else { return nil }
        return imageProperties[String(kCGImagePropertyGIFDictionary)] as? GIFProperties
    }
}

/// A `UIImage` extension that makes it easier to resize the image and inspect its size.
extension UIImage {
    /// Resizes an image instance.
    ///
    /// - parameter size: The new size of the image.
    /// - returns: A new resized image instance.
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        self.draw(in: CGRect(origin: CGPoint.zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
    
    /// Resizes an image instance to fit inside a constraining size while keeping the aspect ratio.
    ///
    /// - parameter size: The constraining size of the image.
    /// - returns: A new resized image instance.
    func constrained(by constrainingSize: CGSize) -> UIImage {
        let newSize = size.constrained(by: constrainingSize)
        return resized(to: newSize)
    }
    
    /// Resizes an image instance to fill a constraining size while keeping the aspect ratio.
    ///
    /// - parameter size: The constraining size of the image.
    /// - returns: A new resized image instance.
    func filling(size fillingSize: CGSize) -> UIImage {
        let newSize = size.filling(fillingSize)
        return resized(to: newSize)
    }
    
    /// Returns a new `UIImage` instance using raw image data and a size.
    ///
    /// - parameter data: Raw image data.
    /// - parameter size: The size to be used to resize the new image instance.
    /// - returns: A new image instance from the passed in data.
    class func image(with data: Data, size: CGSize) -> UIImage? {
        return UIImage(data: data)?.resized(to: size)
    }
    
    /// Returns an image size from raw image data.
    ///
    /// - parameter data: Raw image data.
    /// - returns: The size of the image contained in the data.
    class func size(withImageData data: Data) -> CGSize? {
        return UIImage(data: data)?.size
    }
}

extension CGSize {
    /// Calculates the aspect ratio of the size.
    ///
    /// - returns: aspectRatio The aspect ratio of the size.
    var aspectRatio: CGFloat {
        if height == 0 { return 1 }
        return width / height
    }
    
    /// Finds a new size constrained by a size keeping the aspect ratio.
    ///
    /// - parameter size: The contraining size.
    /// - returns: size A new size that fits inside the contraining size with the same aspect ratio.
    func constrained(by size: CGSize) -> CGSize {
        let aspectWidth = round(aspectRatio * size.height)
        let aspectHeight = round(size.width / aspectRatio)
        
        if aspectWidth > size.width {
            return CGSize(width: size.width, height: aspectHeight)
        } else {
            return CGSize(width: aspectWidth, height: size.height)
        }
    }
    
    /// Finds a new size filling the given size while keeping the aspect ratio.
    ///
    /// - parameter size: The contraining size.
    /// - returns: size A new size that fills the contraining size keeping the same aspect ratio.
    func filling(_ size: CGSize) -> CGSize {
        let aspectWidth = round(aspectRatio * size.height)
        let aspectHeight = round(size.width / aspectRatio)
        
        if aspectWidth > size.width {
            return CGSize(width: aspectWidth, height: size.height)
        } else {
            return CGSize(width: size.width, height: aspectHeight)
        }
    }
}

