import Foundation

/// 主料 / 辅料（调料）白名单分类，与 旧数据层 的 SEASONING_KEYWORDS + classifyIngredients 一致。
/// 抓新菜谱时服务端不做分类，落库前在手机上按同一份白名单划分，保证两边端口味一致。
enum IngredientClassifier {
    static let seasoningKeywords: [String] = [
        // 基础调味
        "盐", "糖", "冰糖", "红糖", "白糖", "蜂蜜", "麦芽糖",
        "醋", "米醋", "香醋", "陈醋", "白醋", "苹果醋",
        "酱油", "生抽", "老抽", "蒸鱼豉油", "味极鲜", "蚝油", "甜面酱油",
        "料酒", "黄酒", "米酒", "白酒",
        // 油脂
        "油", "食用油", "植物油", "花生油", "玉米油", "菜籽油", "大豆油", "葵花籽油",
        "色拉油", "猪油", "黄油", "牛油", "羊油", "椰子油", "牛至油",
        "香油", "麻油", "芝麻油", "辣椒油", "花椒油", "藤椒油",
        // 香辛料
        "葱", "大葱", "小葱", "香葱", "葱花", "葱段", "葱末", "京葱",
        "姜", "生姜", "姜末", "姜丝", "姜片",
        "蒜", "大蒜", "蒜末", "蒜瓣", "蒜泥", "蒜蓉",
        "八角", "大料", "桂皮", "香叶", "花椒", "麻椒", "藤椒",
        "胡椒", "黑胡椒", "白胡椒", "胡椒粉",
        "辣椒", "干辣椒", "朝天椒", "小米辣", "小米椒", "辣椒粉", "辣椒面",
        "五香粉", "十三香", "卤料", "卤料包", "炖肉料", "卤汁",
        // 增鲜/酱料
        "味精", "鸡精", "鸡粉", "浓缩鸡汁", "太太乐",
        "豆瓣酱", "郫县豆瓣酱", "郫县豆瓣", "甜面酱", "黄豆酱", "豆瓣", "豆豉",
        "番茄酱", "番茄沙司", "沙拉酱", "辣椒酱", "老干妈", "海鲜酱", "XO酱", "柱侯酱", "叉烧酱",
        // 淀粉/粉
        "淀粉", "玉米淀粉", "土豆淀粉", "红薯淀粉", "生粉", "糯米粉", "低筋面粉", "中筋面粉", "高筋面粉", "面粉",
        // 液体
        "水", "温水", "冷水", "热水", "清水", "冰水", "凉水",
        "高汤", "鸡汤", "骨汤", "肉汤", "鱼汤", "蔬菜汤", "浓汤宝",
        // 发酵/膨松
        "酵母", "泡打粉", "小苏打", "碱", "碱水",
        // 其他常见调料
        "茶叶", "茶叶蛋料包", "红茶", "绿茶", "普洱",
        "草果", "砂仁", "白蔻", "肉蔻", "丁香", "小茴香",
        "陈皮", "香茅", "罗勒", "迷迭香", "百里香", "欧芹",
        "香菜", "芹菜", "薄荷", "紫苏",
    ]

    /// 复合名（"姜末"、"郫县豆瓣酱"）也能命中白名单里的根词
    static func isSeasoning(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for keyword in seasoningKeywords where trimmed.contains(keyword) {
            return true
        }
        return false
    }

    static func classify(_ ingredients: [IngredientItem]) -> IngredientGroups {
        var main: [IngredientItem] = []
        var seasoning: [IngredientItem] = []
        for item in ingredients where !item.name.isEmpty {
            if isSeasoning(item.name) {
                seasoning.append(item)
            } else {
                main.append(item)
            }
        }
        return IngredientGroups(main: main, seasoning: seasoning)
    }
}
