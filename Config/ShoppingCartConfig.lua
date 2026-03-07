local Config = {
    -- 商品数量（左侧货架）。
    MAX_PRODUCTS           = 6,

    -- 左侧货架每行商品位数量：
    -- 商品映射规则按 PRODUCT_CONFIG 顺序从左到右、从上到下自动绑定。
    -- 例如（每行2个）：
    -- 第1个商品 -> LineItem_1_1
    -- 第2个商品 -> LineItem_1_2
    -- 第3个商品 -> LineItem_2_1
    GRID_ITEMS_PER_LINE    = 2,

    -- 右侧购物车预创建清单行数上限：
    -- 实际展示行数会在运行时按 UINodes 中实际存在的 Item_i 自动检测。
    MAX_CART_ROWS          = 6,

    -- 单个商品可购买最大数量（加号按钮上限保护）。
    MAX_AMOUNT_PER_PRODUCT = 999,

    -- 商品基础配置（可直接扩展测试数据）：
    -- productId: 业务商品ID（建议使用 10001 这类真实ID）
    -- 映射规则：按数组顺序绑定到左侧货架（左->右、上->下）
    -- name: 商品显示名 -> 左侧 ItemName_*_*，右侧 ItemNameLabel_*
    -- unitPrice: 单个商品单价 -> 左侧 UnitPrice_*_*（单价显示）
    -- caseCount: 每箱包含数量 -> 左侧 AmountLabel_*_*（本需求统一 12）
    PRODUCT_CONFIG = {
        {
            productId = 10001,
            name      = "大果软糖",
            unitPrice = 9.99,
            caseCount = 12,
        },
        {
            productId = 10002,
            name      = "薄荷糖",
            unitPrice = 12.80,
            caseCount = 12,
        },
        {
            productId = 10003,
            name      = "牛奶巧克力",
            unitPrice = 25.50,
            caseCount = 12,
        },
        {
            productId = 10004,
            name      = "柠檬糖",
            unitPrice = 9.90,
            caseCount = 12,
        },
        {
            productId = 10005,
            name      = "咖啡糖",
            unitPrice = 15.00,
            caseCount = 12,
        },
        {
            productId = 10006,
            name      = "草莓糖",
            unitPrice = 18.80,
            caseCount = 12,
        },
    },

    -- 左侧选购区节点命名规则（按 line/col 自动拼接：prefix .. "_" .. line .. "_" .. col）。
    LEFT_GRID_NODE_NAMING = {
        itemNamePrefix            = "ItemName",            -- 商品名文本
        unitPricePrefix           = "UnitPrice",           -- 单价文本（单个）
        amountLabelPrefix         = "AmountLabel",         -- 每箱件数文本（默认 12）
        purchaseAmountLabelPrefix = "PurchaseAmountLabel", -- 待加入购物车的箱数文本
        casePriceLabelPrefix      = "CasePriceLabel",      -- 待加入购物车总价文本
        addButtonPrefix           = "AddBtn",              -- 左侧加号按钮（增加待购箱数）
        decButtonPrefix           = "DecBtn",              -- 左侧减号按钮（减少待购箱数）
        purchaseButtonPrefix      = "PurchaseBtn",         -- 左侧提交按钮（加入右侧清单）
    },

    -- 右侧清单节点命名规则（按 row 自动拼接：prefix .. "_" .. row）。
    RIGHT_LIST_NODE_NAMING = {
        rootPrefix      = "Item",               -- 单行根节点（Item_{row}）
        itemNamePrefix  = "ItemNameLabel",      -- 单行商品名文本
        subTotalPrefix  = "ItemTotalValueLabel", -- 单行小计文本
        amountPrefix    = "ItemAmountLabel",    -- 单行数量文本
        addButtonPrefix = "CartAddBtn",         -- 单行加号按钮
        decButtonPrefix = "CartDecBtn",         -- 单行减号按钮
    },

    -- 右侧面板公共节点映射（字段含义写在对应行后面）。
    CART_PANEL_NODE_NAMES = {
        root                     = "CartFrame",                 -- 右侧购物车根容器
        cartTitle                = "CartTextLabel",             -- 顶部标题文本（购物车）
        listTitleRoot            = "ListTitleFrame",            -- 列表标题行容器
        listTitleItemName        = "ItemNameTitleLabel",        -- 标题-商品项
        listTitleItemTotalValue  = "ItemTotaValueTitleLabel",   -- 标题-小计（导出拼写原样保留）
        listTitleItemAmount      = "ItemAmountTitleLabel",      -- 标题-数量
        listRoot                 = "ItemListFrame",             -- 清单列表容器
        totalRoot                = "CartTotalFrame",            -- 总价区域容器
        totalText                = "TotalTextLabel",            -- “总计”文本
        totalValue               = "TotalValueLabel",           -- 所有商品总价
        buttonRoot               = "CartBtnFrame",              -- 底部按钮区域容器
        purchaseButton           = "PurchaseConfirmBtn",        -- 结算按钮
        purchaseButtonText       = "PurchaseConfirmTextLabel",  -- 结算按钮文本（购买）
        clearButton              = "ClearBtn",                  -- 清空按钮
        clearButtonIcon          = "ClearImageLabel",           -- 清空按钮图标节点
    },

    -- UI 节点触摸事件类型（ENodeTouchEventType）：
    -- 默认使用 1；若引擎侧点击类型不同，可改成 2 或扩展成 {1, 2}。
    UI_TOUCH_EVENT_TYPES = {
        1,
    },
}

return Config
