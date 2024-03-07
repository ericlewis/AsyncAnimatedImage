## Example

https://github.com/ericlewis/AsyncAnimatedImage/assets/674503/8347cc5a-6f0f-458a-845e-2463c0250980

```swift
let url = URL(string: "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_5d523adb8bbb4786821cd7091e47da21/default/dark/2.0")!

struct CellView: View {
    var body: some View {
        Text("CHOMPCHOMP: \(AsyncAnimatedImage(url: url))")
            .drawingGroup() // this is useful when you are using lots of GIFs
    }
}
```

