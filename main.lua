-- ========================================
-- CHATMINI - AI Chatbot Full Features
-- BY FDLOL - Complete Free Version
-- ========================================

local widget = require("widget")
local json = require("json")
local network = require("network")
local sqlite3 = require("sqlite3")

-- ========== CONFIG ==========
local W, H = display.contentWidth, display.contentHeight
local API_KEY = "AQ.Ab8RN6JyHFJEgkT4fMDcWFhnUJmN43FTnHfIUtPRI0L5ljwD6g"
local API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=" .. API_KEY
local SEARCH_URL = "https://api.duckduckgo.com/"

-- ========== MÀU SẮC ==========
local COLORS = {
    bg = {0.07, 0.07, 0.09},
    header = {0.11, 0.11, 0.13},
    userBubble = {0.2, 0.45, 0.8},
    aiBubble = {0.15, 0.15, 0.18},
    thinkingBubble = {0.25, 0.2, 0.15},
    text = {1, 1, 1},
    textSecondary = {0.6, 0.6, 0.65},
    inputBg = {0.12, 0.12, 0.15},
    border = {0.2, 0.2, 0.25},
    accent = {0.3, 0.6, 1.0}
}

-- ========== DATABASE ==========
local db = sqlite3.open("chatmini.db")
db:exec[[
    CREATE TABLE IF NOT EXISTS chat_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT,
        role TEXT,
        content TEXT,
        timestamp TEXT
    );
]]

-- ========== BIẾN TOÀN CỤC ==========
local currentChatId = nil
local messages = {}
local msgY = 20
local chatView = nil
local inputBox = nil
local isThinking = false
local webSearchEnabled = false

-- ========== KIỂM TRA GIỚI HẠN 100 CHAT ==========
local function checkChatLimit()
    local count = db:first_row("SELECT COUNT(DISTINCT chat_id) as total FROM chat_history")
    local total = count and count.total or 0
    
    if total >= 100 then
        local oldest = db:first_row("SELECT DISTINCT chat_id FROM chat_history ORDER BY timestamp ASC LIMIT 1")
        if oldest then
            db:exec("DELETE FROM chat_history WHERE chat_id = ?", oldest.chat_id)
            showToast("🔄 Đã xóa chat cũ nhất (giới hạn 100)")
        end
    end
end

-- ========== TẠO PROMISE ==========
local function newPromise(executor)
    local self = {}
    local callbacks = {}
    local errorCallbacks = {}
    local resolved = false
    local rejected = false
    local value = nil
    local error = nil
    
    function self:then(callback)
        if resolved then
            callback(value)
        else
            table.insert(callbacks, callback)
        end
        return self
    end
    
    function self:catch(callback)
        if rejected then
            callback(error)
        else
            table.insert(errorCallbacks, callback)
        end
        return self
    end
    
    local function resolve(val)
        if not resolved and not rejected then
            resolved = true
            value = val
            for _, cb in ipairs(callbacks) do
                cb(val)
            end
        end
    end
    
    local function reject(err)
        if not resolved and not rejected then
            rejected = true
            error = err
            for _, cb in ipairs(errorCallbacks) do
                cb(err)
            end
        end
    end
    
    executor(resolve, reject)
    return self
end

-- ========== HÀM TÌM KIẾM WEB ==========
local function searchWeb(query)
    return newPromise(function(resolve, reject)
        local encodedQuery = query:gsub(" ", "+"):gsub("%?", "")
        local url = SEARCH_URL .. "?q=" .. encodedQuery .. "&format=json&no_html=1&skip_disambig=1"
        
        print("🔍 Searching:", url)
        
        network.request(
            url,
            "GET",
            function(event)
                if event.isError then
                    reject("Lỗi kết nối: " .. event.errorMessage)
                    return
                end
                
                local data = json.decode(event.response)
                
                if data then
                    if data.AbstractText and data.AbstractText ~= "" then
                        resolve(data.AbstractText)
                        return
                    end
                    
                    if data.RelatedTopics and #data.RelatedTopics > 0 then
                        local results = {}
                        for i = 1, math.min(3, #data.RelatedTopics) do
                            if data.RelatedTopics[i].Text then
                                table.insert(results, data.RelatedTopics[i].Text)
                            end
                        end
                        if #results > 0 then
                            resolve(table.concat(results, "\n\n"))
                            return
                        end
                    end
                    
                    if data.Abstract and data.Abstract ~= "" then
                        resolve(data.Abstract)
                        return
                    end
                end
                
                reject("Không tìm thấy thông tin cho: " .. query)
            end,
            nil,
            { ["Content-Type"] = "application/json" }
        )
    end)
end

-- ========== TẠO GIAO DIỆN ==========
local function createMainUI()
    -- Background
    local bg = display.newRect(0, 0, W, H)
    bg:setFillColor(unpack(COLORS.bg))
    
    -- Header
    local header = display.newRect(0, 0, W, 110)
    header:setFillColor(unpack(COLORS.header))
    header.x, header.y = W/2, 55
    
    -- Logo
    local logoText = display.newText({
        text = "⚡ CHATMINI",
        x = W/2, y = 40,
        fontSize = 22,
        font = native.systemFontBold
    })
    logoText:setFillColor(1, 1, 1)
    
    -- BY FDLOL
    local byText = display.newText({
        text = "BY FDLOL",
        x = W/2, y = 64,
        fontSize = 12,
        font = native.systemFont
    })
    byText:setFillColor(unpack(COLORS.textSecondary))
    
    -- Số chat
    local function updateChatCount()
        local count = db:first_row("SELECT COUNT(DISTINCT chat_id) as total FROM chat_history")
        local total = count and count.total or 0
        return total
    end
    
    local chatCountText = display.newText({
        text = "📊 " .. updateChatCount() .. "/100 chat",
        x = W/2, y = 88,
        fontSize = 11,
        font = native.systemFont
    })
    chatCountText:setFillColor(unpack(COLORS.textSecondary))
    
    -- ========== NÚT TẠO CHAT MỚI ==========
    local newChatBtn = widget.newButton({
        x = 35, y = 55,
        width = 40, height = 40,
        label = "✚",
        labelColor = { default = {1,1,1}, over = {0.7,0.7,0.7} },
        fontSize = 28,
        shape = "circle",
        fillColor = { default = {0.3,0.3,0.35}, over = {0.2,0.2,0.25} },
        onPress = function()
            checkChatLimit()
            createNewChat()
            chatCountText.text = "📊 " .. updateChatCount() .. "/100 chat"
        end
    })
    
    -- ========== NÚT LỊCH SỬ CHAT ==========
    local historyBtn = widget.newButton({
        x = W - 35, y = 55,
        width = 40, height = 40,
        label = "📋",
        labelColor = { default = {1,1,1}, over = {0.7,0.7,0.7} },
        fontSize = 22,
        shape = "circle",
        fillColor = { default = {0.3,0.3,0.35}, over = {0.2,0.2,0.25} },
        onPress = function()
            showChatHistory()
        end
    })
    
    -- ========== NÚT WEB SEARCH ==========
    local webBtn = widget.newButton({
        x = 80, y = 90,
        width = 35, height = 25,
        label = "🌐",
        labelColor = { default = {0.6,0.6,0.6}, over = {0.8,0.8,0.8} },
        fontSize = 16,
        fillColor = { default = {0.2,0.2,0.25}, over = {0.3,0.3,0.35} },
        onPress = function()
            webSearchEnabled = not webSearchEnabled
            webBtn:setFillColor(
                webSearchEnabled and {0.2, 0.5, 0.3} or {0.2, 0.2, 0.25}
            )
            webBtn.labelColor = {
                default = webSearchEnabled and {0.3, 0.9, 0.4} or {0.6, 0.6, 0.6},
                over = webSearchEnabled and {0.5, 1, 0.6} or {0.8, 0.8, 0.8}
            }
            showToast(webSearchEnabled and "✅ Web Search ON" or "❌ Web Search OFF")
        end
    })
    
    -- ========== CHAT VIEW ==========
    chatView = widget.newScrollView({
        x = 0, y = 110,
        width = W, height = H - 180,
        scrollWidth = W,
        scrollHeight = 0,
        hideBackground = true,
        horizontalScrollDisabled = true,
        backgroundColor = { unpack(COLORS.bg) }
    })
    
    -- ========== INPUT AREA ==========
    local inputBg = display.newRect(0, H - 60, W, 55)
    inputBg:setFillColor(unpack(COLORS.inputBg))
    inputBg:setStrokeColor(unpack(COLORS.border))
    inputBg.strokeWidth = 1
    
    inputBox = native.newTextBox(W/2 - 20, H - 40, W - 85, 40)
    inputBox.placeholder = "Nhập tin nhắn..."
    inputBox.font = native.systemFont
    inputBox.size = 16
    inputBox.hasBackground = false
    inputBox:setFillColor(0, 0, 0, 0.3)
    inputBox:setTextColor(1, 1, 1)
    
    local sendBtn = widget.newButton({
        x = W - 30, y = H - 40,
        width = 40, height = 40,
        label = "➤",
        labelColor = { default = {1,1,1}, over = {0.7,0.7,0.7} },
        fontSize = 20,
        shape = "circle",
        fillColor = { default = {0.2, 0.45, 0.8}, over = {0.15, 0.35, 0.7} },
        onPress = function()
            if isThinking then
                showToast("⏳ Đang suy nghĩ, đợi tí nhé!")
                return
            end
            sendToGemini()
        end
    })
    
    -- ========== HÀM TẠO CHAT MỚI ==========
    function createNewChat()
        checkChatLimit()
        currentChatId = os.time() .. "_" .. math.random(1000, 9999)
        messages = {}
        msgY = 20
        
        chatView:removeSelf()
        chatView = widget.newScrollView({
            x = 0, y = 110,
            width = W, height = H - 180,
            scrollWidth = W,
            scrollHeight = 0,
            hideBackground = true,
            horizontalScrollDisabled = true,
            backgroundColor = { unpack(COLORS.bg) }
        })
        
        addMessage("🆕 Chat mới!", false)
        addMessage("👋 Hỏi tôi bất cứ điều gì!", false)
        addMessage("🌐 Bật Web Search để tìm thông tin trực tuyến", false)
        showToast("✅ Đã tạo chat mới!")
    end
    
    -- ========== HÀM HIỂN THỊ LỊCH SỬ ==========
    function showChatHistory()
        local popupBg = display.newRect(0, 0, W, H)
        popupBg:setFillColor(0, 0, 0, 0.7)
        popupBg:addEventListener("tap", function() popupBg:removeSelf() end)
        
        local popup = display.newRoundedRect(W/2, H/2, W - 40, H - 100, 15)
        popup:setFillColor(0.15, 0.15, 0.2)
        
        local title = display.newText({
            text = "📋 Lịch sử chat",
            x = W/2, y = H/2 - H/3 + 40,
            fontSize = 18,
            font = native.systemFontBold
        })
        title:setFillColor(1, 1, 1)
        
        local historyList = {}
        for row in db:nrows("SELECT DISTINCT chat_id, timestamp FROM chat_history ORDER BY timestamp DESC LIMIT 100") do
            table.insert(historyList, row)
        end
        
        local yPos = H/2 - H/3 + 80
        for i, item in ipairs(historyList) do
            if yPos > H/2 + H/3 - 50 then break end
            
            local chatItem = display.newRect(W/2, yPos, W - 80, 40)
            chatItem:setFillColor(0.2, 0.2, 0.25)
            chatItem:addEventListener("tap", function()
                loadChatHistory(item.chat_id)
                popupBg:removeSelf()
            end)
            
            local chatText = display.newText({
                text = "Chat " .. os.date("%H:%M %d/%m", tonumber(item.timestamp) or 0),
                x = W/2, y = yPos,
                fontSize = 14,
                font = native.systemFont
            })
            chatText:setFillColor(0.8, 0.8, 0.9)
            
            yPos = yPos + 50
        end
        
        if #historyList == 0 then
            local emptyText = display.newText({
                text = "📭 Chưa có lịch sử chat",
                x = W/2, y = H/2,
                fontSize = 16,
                font = native.systemFont
            })
            emptyText:setFillColor(unpack(COLORS.textSecondary))
        end
        
        local closeBtn = widget.newButton({
            x = W/2, y = H - 50,
            width = 100, height = 40,
            label = "Đóng",
            shape = "roundedRect",
            fillColor = { default = {0.3, 0.3, 0.35}, over = {0.2, 0.2, 0.25} },
            onPress = function()
                popupBg:removeSelf()
            end
        })
    end
    
    -- ========== HÀM LOAD LỊCH SỬ ==========
    function loadChatHistory(chatId)
        currentChatId = chatId
        messages = {}
        msgY = 20
        
        chatView:removeSelf()
        chatView = widget.newScrollView({
            x = 0, y = 110,
            width = W, height = H - 180,
            scrollWidth = W,
            scrollHeight = 0,
            hideBackground = true,
            horizontalScrollDisabled = true,
            backgroundColor = { unpack(COLORS.bg) }
        })
        
        for row in db:nrows("SELECT * FROM chat_history WHERE chat_id = ? ORDER BY timestamp ASC", chatId) do
            addMessage(row.content, row.role == "user", false)
        end
        
        showToast("📂 Đã tải lịch sử chat!")
    end
    
    -- ========== HÀM THÊM TIN NHẮN ==========
    function addMessage(text, isUser, saveToDB)
        if #text > 4000 then
            text = text:sub(1, 4000) .. "..."
        end
        
        local bgColor = isUser and COLORS.userBubble or COLORS.aiBubble
        if text:find("⏳") or text:find("🔍") then
            bgColor = COLORS.thinkingBubble
        end
        
        local align = isUser and "right" or "left"
        local xPos = isUser and W - 20 or 20
        
        local bubble = display.newRoundedRect(xPos, msgY, W - 40, 30, 12)
        bubble:setFillColor(unpack(bgColor))
        bubble.anchorX = isUser and 1 or 0
        
        local msg = display.newText({
            text = text,
            x = xPos - (isUser and 18 or 18),
            y = msgY,
            width = W - 75,
            fontSize = 15,
            font = native.systemFont,
            align = align
        })
        msg:setFillColor(unpack(COLORS.text))
        msg.anchorX = isUser and 1 or 0
        
        local padding = 15
        local h = msg.height + padding * 2
        bubble.height = math.max(h, 35)
        msg.y = bubble.y
        
        table.insert(messages, { bubble = bubble, text = msg })
        msgY = msgY + bubble.height + 8
        
        if saveToDB ~= false and currentChatId then
            local role = isUser and "user" or "assistant"
            db:exec("INSERT INTO chat_history (chat_id, role, content, timestamp) VALUES (?, ?, ?, ?)",
                currentChatId, role, text, os.time())
            checkChatLimit()
        end
        
        chatView:scrollToPosition({ y = msgY - chatView.height + 50 })
        chatView:setScrollHeight(math.max(msgY + 50, chatView.height))
    end
    
    -- ========== HÀM GỬI TIN NHẮN ==========
    function sendToGemini()
        if not inputBox then return end
        
        local question = inputBox.text
        if not question or question == "" then
            showToast("⚠️ Vui lòng nhập câu hỏi!")
            return
        end
        
        isThinking = true
        addMessage(question, true)
        inputBox.text = ""
        
        -- Hiển thị đang suy nghĩ
        local thinkingMsg = "⏳ Đang suy nghĩ"
        local dots = 0
        local thinkingTimer = timer.performWithDelay(400, function()
            dots = (dots + 1) % 4
            local dotsStr = string.rep(".", dots)
            if messages[#messages] then
                messages[#messages].text.text = thinkingMsg .. dotsStr
            end
        end, 0)
        
        local function processQuery(searchResult)
            local prompt = question
            if searchResult then
                prompt = "Câu hỏi: " .. question .. "\n\n"
                prompt = prompt .. "Thông tin tìm kiếm được:\n" .. searchResult .. "\n\n"
                prompt = prompt .. "Dựa trên thông tin trên, hãy trả lời câu hỏi một cách chính xác và đầy đủ."
            end
            
            local payload = {
                contents = {
                    {
                        parts = {
                            { text = prompt }
                        }
                    }
                },
                generationConfig = {
                    temperature = 0.6,
                    maxOutputTokens = 1500,
                    topP = 0.95,
                    topK = 40
                }
            }
            
            local headers = {
                ["Content-Type"] = "application/json"
            }
            
            network.request(
                API_URL,
                "POST",
                function(event)
                    timer.cancel(thinkingTimer)
                    
                    if messages[#messages] then
                        messages[#messages].bubble:removeSelf()
                        messages[#messages].text:removeSelf()
                        table.remove(messages)
                        msgY = msgY - (messages[#messages] and messages[#messages].bubble.height + 8 or 40)
                    end
                    
                    isThinking = false
                    
                    if event.isError then
                        addMessage("❌ Lỗi mạng: " .. event.errorMessage, false)
                        return
                    end
                    
                    local data = json.decode(event.response)
                    
                    if data and data.candidates and data.candidates[1] then
                        local content = data.candidates[1].content
                        if content and content.parts and content.parts[1] then
                            local response = content.parts[1].text
                            if searchResult then
                                response = "🌐 " .. response
                            end
                            addMessage(response, false)
                            return
                        end
                    end
                    
                    local errorMsg = "❌ "
                    if data and data.error then
                        errorMsg = errorMsg .. (data.error.message or "Unknown error")
                    else
                        errorMsg = errorMsg .. "Không thể parse response"
                    end
                    addMessage(errorMsg, false)
                    print("Response:", event.response)
                end,
                json.encode(payload),
                headers
            )
        end
        
        -- Nếu bật web search
        if webSearchEnabled then
            if messages[#messages] then
                messages[#messages].text.text = "🔍 Đang tìm kiếm trên web..."
            end
            
            searchWeb(question)
                :then(function(result)
                    if messages[#messages] then
                        messages[#messages].text.text = "🧠 Đang phân tích thông tin..."
                    end
                    processQuery(result)
                end)
                :catch(function(err)
                    print("Web search error:", err)
                    if messages[#messages] then
                        messages[#messages].text.text = "💭 Đang suy nghĩ..."
                    end
                    processQuery(nil)
                end)
        else
            timer.performWithDelay(1500, function()
                processQuery(nil)
            end)
        end
    end
    
    -- ========== HÀM HIỂN THỊ TOAST ==========
    function showToast(message)
        if showToast.obj then
            showToast.obj:removeSelf()
        end
        
        local toast = display.newText({
            text = message,
            x = W/2, y = H - 100,
            fontSize = 14,
            font = native.systemFont
        })
        toast:setFillColor(0.1, 0.1, 0.15, 0.9)
        showToast.obj = toast
        
        timer.performWithDelay(2500, function()
            if toast then toast:removeSelf() end
            showToast.obj = nil
        end)
    end
    
    -- ========== XỬ LÝ BÀN PHÍM ==========
    local function onKey(e)
        if e.phase == "down" and e.keyName == "enter" then
            if isThinking then
                showToast("⏳ Đang suy nghĩ, đợi tí nhé!")
                return
            end
            sendToGemini()
        end
    end
    Runtime:addEventListener("key", onKey)
    
    -- ========== WELCOME ==========
    checkChatLimit()
    currentChatId = os.time() .. "_" .. math.random(1000, 9999)
    
    addMessage("⚡ CHATMINI", false)
    addMessage("BY FDLOL", false)
    addMessage("", false)
    addMessage("👋 Chào bạn!", false)
    addMessage("🧠 Suy nghĩ sâu - Trả lời chính xác", false)
    addMessage("🌐 Bật Web Search để tìm thông tin", false)
    addMessage("📊 Lưu tối đa 100 chat", false)
    addMessage("", false)
    addMessage("✨ Nhấn ✚ để tạo chat mới", false)
    addMessage("📋 Nhấn 📋 để xem lịch sử", false)
    addMessage("🌐 Nhấn nút 🌐 để bật/tắt Web Search", false)
end

-- ========== KHỞI CHẠY ==========
createMainUI()
print("🚀 CHATMINI - BY FDLOL")
print("📱 API Key:", API_KEY:sub(1, 10).."...")
print("💾 Database: SQLite local (100 chat limit)")
print("🌐 Web Search: DuckDuckGo (free)")
