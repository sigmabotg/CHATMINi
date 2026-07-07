-- ========================================
-- CẤU HÌNH APP
-- ========================================

application = {
    content = {
        width = 375,      -- iPhone 6/7/8/SE
        height = 812,     -- iPhone X/11/12/13/14
        scale = "letterbox",
        fps = 60
    },
    
    -- Tự động xoay màn hình
    orientation = {
        default = "portrait",
        supported = { "portrait" }
    }
}
