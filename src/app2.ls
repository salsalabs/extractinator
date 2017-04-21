require! {
    cheerio
    async
    './config'
    css
    'fs-extra': fs
    path
    'prelude-ls': { compact, each, filter, flatten, head, map, reject, replace } 
    request
    url
    './org': { Org }
}

class Base
    @serial-number = 0
    @uri-cache = {}

    (@referer, @elem, @attr) ->
        @content-type = null
        @org = new Org()
        @protocol = null
        @resolved = null
        @uri = @elem[@attr]

    clean-basename: (v) -> v .split /[\?\&\;\#]/ .0

    get-basename: ->
        basename = (path.basename @resolved .split '?')[0]
        return @clean-basename basename if path.extname basename .length > 0
        extension = (@content-type .split '/' .1)
        return @clean-basename "#{basename || ++@@serial-number}.#{extension}"

    get-directory: ->
        | /image\//.test @content-type => \image
        | /css/.test @content-type => \css
        | /javascript/.test @content-type => \javascript
        | /font/.test @content-type => \font
        | otherwise ''

    get-resolved: ->
        return @uri-cache[@uri] if @uri in @uri-cache

        url-obj = url.parse @uri
        return @uri if url-obj.host in config.CDN_HOSTS
        @protocol = url-obj .protocol
        return @uri if @protocol == 'data'
        referer = switch @referer | null =>@org.uri | otherwise => @referer
        try unless @protocol?
            @resolved url.resolve @referer, @uri
        catch thrown
            console.error "URL.resolve threw #{thrown}"
            console.error "referer is #{@referer}"
            console.error "original is #{@uri}"
            console.error "\n"
            @resoived = @url

        @uri-cache[@uri] = @resolved
        @resolved

    process: (body, cb) -> cb null, body

    request: request.defaults do
        jar: true
        encoding: null
        headers:
            'Referer':@org.uri
            'User-Agent': config.USER_AGENT    

    # returns (err, body)
    fetch (cb) ->
        cb null, null if @protocol == 'data'
        (err, resp, body) <~ @request @resolved!
        if err?
            console.err "fetch caught #{err} on {#resolved!}"
            return cb null, null
        @content-type = resp.headers.'content-type'
        return cb null, body if resp.status-code == 200
        cb null, null

    # returns (err)
    save (buffer, cb) ->
        # console.error "save-buffer-to-disk: #{@to-string!}"
        @filename = path.join org.dir, @get-directory!, @get-basename!
        local-filename = switch @filename.slice 0 1
            | '/' => @filename.slice 1
            | otherwise => @filename
        target-dir = path.dirname local-filename
        err <~ fs.mkdirs target-dir
        console.error "save-buffer-to-dir mkdirs returned #err" if err?
        return cb null if err?

        err <~ fs.writeFile local-filename, body, encoding: null
        return cb err

class CSSHandler extends Base
    process(body, cb) ->
        try
            obj = css.parse body.toString!, silent: true, source: @referer
            return cb null, body unless obj.stylesheet?
            return cb null, body unless obj.stylesheet.rules?
            rules = obj.stylesheet.rules.map (@attr)
            err <~ async.each rules, process-rule
            return cb null, css.stringify obj
        catch thrown
            console.error "process-css-buffer: caught css.stringify error #{thrown}"
            return cb null, body

    process-rule(rule, cb) ->
        return cb null unless @attr in rule
        obj = new Base (@uri or @referer), rule, @attr
        (err, buffer) <- obj.fetch!
        console.error "CSSHandler: #{err} while processing #{rule[@attr]}" if err?
        return cb null if err?
        console.error "CSSHandler: empty buffer while processing #{rule[@attr]}" unless buffer?
        return cb null not buffer?
        (err, filename) <-@save buffer
        console.error "CSSHandler: #{err} while saving #{rule[@attr]}" if err?
        rule[@attr] = @filename
        console.log "CSSHander: saved @filename"

        