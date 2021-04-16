def split_outer_method_call(str)
    stack = []
    first = false
    parenthesis = 0
    str.each_char.with_index do |c, i|
        case c
        when '('
            parenthesis += 1
            if parenthesis == 1
                stack.push(i+1)
                first = true
            end
        when ','
            if parenthesis == 1
                stack.push(i+1)
            end
        when ')'
            parenthesis -= 1
            if parenthesis == 0
                stack.push(i)
            end
        end
    end

    stack.push(str.length)

    out = []
    s = 0
    stack.each do |i|
        out.push(str[s...i].lstrip.chomp(', '))
        s = i
    end
    out[1...-1]
end

