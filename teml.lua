local patterns = {
    var = {"$(%w+)",function(temp,s)
        return temp[s:match "^%d+$" and tonumber(s) or s]
    end},

    enclosed_var = {"$%((%w+)%)",function(temp,s)
        return temp[s:match "^%d+$" and tonumber(s) or s]
    end}
}

local function teml(str)
    return function(temp)
        for _,v in pairs(patterns) do
            str = str:gsub("("..v[1]..")",function(_,...)
                return v[2](temp,...)
            end)
        end
        return str
    end
end

return teml
