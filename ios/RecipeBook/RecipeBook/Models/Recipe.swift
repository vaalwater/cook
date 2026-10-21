import Foundation

struct IngredientItem: Codable, Hashable {
    var name: String
    var amount: String

    init(name: String = "", amount: String = "") {
        self.name = name
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey { case name, amount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.amount = (try? c.decode(String.self, forKey: .amount)) ?? ""
    }
}

struct IngredientGroups: Codable, Hashable {
    var main: [IngredientItem]
    var seasoning: [IngredientItem]

    init(main: [IngredientItem] = [], seasoning: [IngredientItem] = []) {
        self.main = main
        self.seasoning = seasoning
    }

    private enum CodingKeys: String, CodingKey { case main, seasoning }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.main = (try? c.decode([IngredientItem].self, forKey: .main)) ?? []
        self.seasoning = (try? c.decode([IngredientItem].self, forKey: .seasoning)) ?? []
    }
}

struct RecipeStep: Codable, Hashable, Identifiable {
    var index: Int
    var text: String
    var image: String

    var id: Int { index }

    init(index: Int = 0, text: String = "", image: String = "") {
        self.index = index
        self.text = text
        self.image = image
    }

    private enum CodingKeys: String, CodingKey { case index, text, image }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.index = (try? c.decode(Int.self, forKey: .index)) ?? 0
        self.text = (try? c.decode(String.self, forKey: .text)) ?? ""
        self.image = (try? c.decode(String.self, forKey: .image)) ?? ""
    }
}

struct Recipe: Codable, Hashable, Identifiable {
    var id: Int
    var url: String
    var title: String
    var description: String
    var coverImage: String
    var author: String
    var servings: String
    var ingredients: [IngredientItem]
    var ingredientGroups: IngredientGroups
    var steps: [RecipeStep]
    var tips: String
    var tags: [String]
    var madeCount: String
    var favCount: String
    var sourceUrl: String
    var collectedAt: String
    var updatedAt: String

    /// 归一化后的检索索引（与网页端 search_text 同规则），不写入 JSON
    var searchIndex: String = ""

    private enum CodingKeys: String, CodingKey {
        case id, url, title, description, coverImage, author, servings
        case ingredients, ingredientGroups, steps, tips, tags
        case madeCount, favCount, sourceUrl, collectedAt, updatedAt
    }

    /// 抓取写入用：按字段构造，索引自动算好
    init(
        id: Int,
        url: String = "",
        title: String = "",
        description: String = "",
        coverImage: String = "",
        author: String = "",
        servings: String = "",
        ingredients: [IngredientItem] = [],
        ingredientGroups: IngredientGroups = IngredientGroups(),
        steps: [RecipeStep] = [],
        tips: String = "",
        tags: [String] = [],
        madeCount: String = "",
        favCount: String = "",
        sourceUrl: String = "",
        collectedAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.description = description
        self.coverImage = coverImage
        self.author = author
        self.servings = servings
        self.ingredients = ingredients
        self.ingredientGroups = ingredientGroups
        self.steps = steps
        self.tips = tips
        self.tags = tags
        self.madeCount = madeCount
        self.favCount = favCount
        self.sourceUrl = sourceUrl
        self.collectedAt = collectedAt
        self.updatedAt = updatedAt
        self.searchIndex = ""
        self.searchIndex = TextIndex.buildIndex(for: self)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.url = (try? c.decode(String.self, forKey: .url)) ?? ""
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.description = (try? c.decode(String.self, forKey: .description)) ?? ""
        self.coverImage = (try? c.decode(String.self, forKey: .coverImage)) ?? ""
        self.author = (try? c.decode(String.self, forKey: .author)) ?? ""
        self.servings = (try? c.decode(String.self, forKey: .servings)) ?? ""
        self.ingredients = (try? c.decode([IngredientItem].self, forKey: .ingredients)) ?? []
        self.ingredientGroups = (try? c.decode(IngredientGroups.self, forKey: .ingredientGroups)) ?? IngredientGroups()
        self.steps = (try? c.decode([RecipeStep].self, forKey: .steps)) ?? []
        self.tips = (try? c.decode(String.self, forKey: .tips)) ?? ""
        self.tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        self.madeCount = (try? c.decode(String.self, forKey: .madeCount)) ?? ""
        self.favCount = (try? c.decode(String.self, forKey: .favCount)) ?? ""
        self.sourceUrl = (try? c.decode(String.self, forKey: .sourceUrl)) ?? ""
        self.collectedAt = (try? c.decode(String.self, forKey: .collectedAt)) ?? ""
        self.updatedAt = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
        self.searchIndex = TextIndex.buildIndex(for: self)
    }

    var displayTitle: String { title.isEmpty ? "未命名" : title }
}

struct SeedManifest: Codable {
    var exportedAt: String = ""
    var recipeCount: Int = 0
    var imageCount: Int = 0
    var imageBytes: Int = 0
    var missingImages: Int = 0
    var remoteImages: Int = 0
    var compressed: Bool = false

    private enum CodingKeys: String, CodingKey {
        case exportedAt, recipeCount, imageCount, imageBytes, missingImages, remoteImages, compressed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.exportedAt = (try? c.decode(String.self, forKey: .exportedAt)) ?? ""
        self.recipeCount = (try? c.decode(Int.self, forKey: .recipeCount)) ?? 0
        self.imageCount = (try? c.decode(Int.self, forKey: .imageCount)) ?? 0
        self.imageBytes = (try? c.decode(Int.self, forKey: .imageBytes)) ?? 0
        self.missingImages = (try? c.decode(Int.self, forKey: .missingImages)) ?? 0
        self.remoteImages = (try? c.decode(Int.self, forKey: .remoteImages)) ?? 0
        self.compressed = (try? c.decode(Bool.self, forKey: .compressed)) ?? false
    }
}
