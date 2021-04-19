require 'json'

require './split.rb'

require 'slop'

VERSION = '0.0.1'

opts = Slop.parse do |o|
    o.banner = 'usage: trim.rb [json_file] [options]'
    o.string '-rg', '--resource-group', 'resource group name'
    o.string '-o', '--output', 'output file path', default:'trimmed.json'
    o.separator ""
    o.separator "other"
    o.on '-v', '--version', 'print the version' do
        puts VERSION
        exit
    end
    o.on '-h', '--help', 'print help' do
        puts o
        exit
    end
end

FILE = opts.arguments[0]
RESOURCE_GROUP = opts[:resource_group]

ID_REGEX = %r'(/subscriptions/[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}(?:/[a-zA-Z0-9\-\.]+)+)'
SUBSCRIPTION_REGEX = %r'(/subscriptions/[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})'
RESOURCEGROUP_REGEX = %r'(/resourcegroups/([^\/]+))'

PROVIDERLESS_REGEX = %r'/subscriptions/[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}(.+)'
PROVIDER_REGEX = %r'/providers/(.+)$'

def each_value(v, path=[], key=nil, parent=nil, &block)
    parent = parent || v

    if v.is_a?(Hash)
        parent = v
        v.each do |k, v|
            newPath = path.clone().push(k)
            each_value(v, newPath, k, parent, &block)
        end
    elsif v.is_a?(Array)
        parent = v
        v.each_with_index do |v, i|
            newPath = path.clone().push('[%d]' % i)
            each_value(v, newPath, i, parent, &block)
        end
    else
        block.call(path, v, key, parent)
    end
end

def hasId(str)
    if str =~ ID_REGEX
        str.scan(ID_REGEX).flatten
    end
end

def joinPath(paths)
    out = ''
    paths.each do |p|
        if p[0] == '['
            out += p
        else
            out += '.' + p
        end
    end
    out[1..-1]
end

def convertId(id, tokens)
    if id.include? "providers"
        resource_group = RESOURCEGROUP_REGEX.match(id).captures[1]

        matches = PROVIDER_REGEX.match(id).captures        
        split = matches[0].split('/')

        type = split[0..1]
        rest = split[2..-1]
        variables = []

        rest.each_slice(2) do |a|
            if a.count == 2
                type.push(a[1])
                variables.push(a[0])
            else
                variables.push(a[0])
            end
        end

        if resource_group != RESOURCE_GROUP
            args = [resource_group]
        else 
            args = []
        end

        args |= [type.join('/')].concat(variables)
    else
        matches = PROVIDERLESS_REGEX.match(id).captures
        split = matches[0].split('/')
        args = [split[1], split[2]]
    end

    args.map! do |a|
        a = ("'%s'" % [a])
        if tokens[a] != nil
            a = tokens[a]
        end
        a
    end

    "[resourceId(%s)]" % [args.join(', ')]
end

obj = JSON.parse(File.read(FILE))

ids = Hash.new()
tokens = Hash.new()

each_value(obj) do |paths, value|
    if value.is_a? String 
        found_ids = hasId(value)
        if found_ids 
            found_ids.each do |id|
                if !ids[id.downcase]
                    ids[id.downcase] = { :paths => [] }
                end
                ids[id.downcase][:paths].push(joinPath(paths))
            end
        end
    end
end

require "tty-prompt"

interrupt = Proc.new {
    puts "\n"
    exit
}

prompt = TTY::Prompt.new(interrupt: interrupt)

ids.each do |id, meta|
    guessed = convertId(id, tokens)

    ids[id][:replace] = prompt.ask("ID was referenced %d times\n%s\nreplace with:\n" % [ meta[:paths].count, id ]) do |q|
        q.value guessed
    end

    if ids[id][:replace] != guessed
        if ids[id][:replace].scan(/resourceId\(/i).count == 1            
            guess_arr   = split_outer_method_call(guessed)
            replace_arr = split_outer_method_call(ids[id][:replace])

            guess_arr.each_with_index do |guess, i|
                if guess != replace_arr[i]
                    tokens[guess] = replace_arr[i]
                end
            end
        end
    end

    puts "\n"
end

sorted_ids = ids.keys.sort_by(&:length).reverse
unique_paths = Hash.new()

ids.each do |id, meta|
    meta[:paths].each do |path|
        if !unique_paths[path]
            unique_paths[path] = []
        end
        unique_paths[path].push(id)
    end
end

each_value(obj) do |paths, value, key, parent|
    if value.is_a? String
        path = joinPath(paths)
        if unique_paths[path]
            if unique_paths[path].count > 1 || value.length != unique_paths[path][0]
                value.gsub! "'", "''"
                value = "[concat('" + value + "')]"
                parent[key] = value
            end
        end
    end
end

each_value(obj) do |paths, value, key, parent|
    if value.is_a? String
        sorted_ids.each do |id|
            meta = ids[id]
            path = joinPath(paths)
            if meta[:paths].include? path
                puts "Replacing %s" % path

                if value.length == id.length
                    parent[key].sub! /#{id}/i, meta[:replace]
                else
                    # todo: this might break if needle is at end of line
                    value = value.split(/#{id}/i)
                                        
                    arg = "', %s, '" % [meta[:replace][1...-1]]
                    value = value.join(arg)
                    parent[key] = value
                end

                #next 2
            end
        end
    end
end

each_value(obj) do |paths, value, key, parent|
    if value.is_a? String
        tokens.each do |token|
            if tokens[value] != nil
                parent[key] = "[%s]" % [tokens[value]]
            end
        end
    end
end

puts "\n"

File.open(opts[:output], 'w') do |f|
    f.write(JSON.pretty_generate(obj))
end