import SwiftUI

struct RecipeImageView: View {
    let path: String
    var placeholderText: String = ""
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(placeholderText.isEmpty ? "🍳" : placeholderText)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: path) {
            guard !path.isEmpty else { return }
            image = await RecipeImageLoader.shared.load(path)
            loaded = true
        }
    }
}

/// 固定比例的图片容器（4:3 等），配合 ScrollView 里不会失控拉高
struct AspectImage: View {
    let path: String
    var ratio: CGFloat = 4.0 / 3.0
    var cornerRadius: CGFloat = 10
    var placeholderText: String = ""

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay(
                RecipeImageView(path: path, placeholderText: placeholderText, cornerRadius: cornerRadius)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
