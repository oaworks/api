
import { customAlphabet } from 'nanoid'

P.uid = (r) ->
  r ?= if @fn is 'uid' then (this?.params?.len ? this?.params?.length ? this?.params?.size ? this?.params?.uid ? 21) else 21
  if typeof r is 'string'
    rs = parseInt r
    r = if isNaN(rs) then undefined else rs
  # have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  # are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  # will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  # without uppercases it's only a 1% chance if generating 1000 IDs per second for 131000 years.
  nanoid = customAlphabet (this?.params?.alphabet ? '0123456789abcdefghijklmnopqrstuvwxyz'), r
  return nanoid()
P.uid._cache = false

P.hash = (content) ->
  content ?= @params.hash ? @params.content ? @params.q ? @params ? @body
  try
    content = await @fetch(@params.url) if @params.url
  content = JSON.stringify(content) if typeof content isnt 'string'
  try
    content = new TextEncoder().encode content
    buf = await crypto.subtle.digest "SHA-256", content
    arr = new Uint8Array buf
    parts = []
    for b in arr
      parts.push ('00' + b.toString(16)).slice(-2)
    return parts.join ''
  catch
    # the above works on CF worker, but crypto.subtle needs to be replaced with standard crypto module on backend
    # crypto is imported by the server-side main api file
    return crypto.createHash('sha256').update(content, 'utf8').digest 'hex' # md5 would be preferable but web crypto /subtle doesn't support md5

P.hashcode = (content) -> # java hash code style
  content ?= @params.hashcode ? @params.content ? @params.q ? @params ? @body
  content = JSON.stringify(content) if typeof content isnt 'string'
  hash = 0
  i = 0
  while i < content.length
    hash = ((hash<<5)-hash) + content.charCodeAt i
    hash &= hash
    i++
  return hash

P.hashhex = (content) ->
  content ?= @params.hashhex
  n = @hashcode content
  n = 0xFFFFFFFF + n + 1 if n < 0
  return n.toString 16

P.shorthash = (content, alphabet) -> # as learnt from something I once googled, but can't remember what
  content ?= @params.shorthash ? @params.content ? @params.q ? @params ? @body
  content = JSON.stringify(content) if typeof content isnt 'string'
  hash = @hashcode content
  if not alphabet
    alphabet = '0123456789abcdefghijklmnoqrstuvwxyz' # keep one char from the usable range to replace negative signs on hashcodes
    spare = 'p'
  else
    spare = alphabet.substring 0, 1
    alphabet = alphabet.replace spare, ''
  al = alphabet.length
  result = if hash < 0 then spare else ''
  hash = Math.abs hash
  while hash >= al
    result += alphabet[hash % al]
    hash = Math.floor hash / al
  return result + (if hash > 0 then alphabet[hash] else '')

P.sleep = (ms) -> # await this when calling it to actually wait
  try ms ?= @params.ms
  return new Promise (resolve) => setTimeout resolve, ms ? 1000
P.sleep._hide = true

P._timeout = (ms, fn) -> # where fn is a promise-able function that has been called
  # so call this like res = await @_timeout 5000, @fetch url
  return new Promise (resolve, reject) =>
    timer = setTimeout () =>
      reject new Error 'TIMEOUT' # should this error or just return undefined?
    , ms
    promise
      .then value =>
        clearTimeout timer
        resolve value
      .catch reason =>
        clearTimeout timer
        reject reason

P.form = (params) ->
  # return params object x-www-form-urlencoded
  params ?= @params
  po = ''
  for p of params
    po += '&' if po isnt ''
    for ppt in (if Array.isArray(params[p]) then params[p] else [params[p]])
      if ppt?
        po += '&' if not po.endsWith '&'
        po += p + '=' + encodeURIComponent (if typeof ppt is 'object' then JSON.stringify(ppt) else ppt)
  return po

P.decode = (content) ->
  content ?= @params.decode ? @params.content ? @params.text ? @body
  _decode = (content) ->
    # https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node
    translator = /&(nbsp|amp|quot|lt|gt);/g
    translate = {
      "nbsp":" ",
      "amp" : "&",
      "quot": "\"",
      "lt"  : "<",
      "gt"  : ">"
    }
    return content.replace(translator, ((match, entity) ->
      return translate[entity]
    )).replace(/&#(\d+);/gi, ((match, numStr) ->
      num = parseInt(numStr, 10)
      return String.fromCharCode(num)
    ))
  text = await _decode content
  text = text.replace /\n/g, ' '
  for c in [{bad: '‘', good: "'"}, {bad: '’', good: "'"}, {bad: '´', good: "'"}, {bad: '“', good: '"'}, {bad: '”', good: '"'}, {bad: '–', good: '-'}, {bad: '-', good: '-'}]
    re = new RegExp c.bad, 'g'
    text = text.replace re, c.good
  text = decodeURIComponent(text) if text.indexOf('%2') isnt -1
  text = decodeURIComponent(text) if text.indexOf('%2') isnt -1 # some of the data we handle was double encoded, so like %2520, so need two decodes
  return text

P.copy = (obj) ->
  try obj ?= @params
  return JSON.parse JSON.stringify obj

P.keys = (obj) ->
  try obj ?= @params
  keys = []
  for k of obj ? {}
    keys.push(k) if obj[k]? and k not in keys
  return keys

P.dot = (obj, key) ->
  # TODO can add back in a way to pass in values or deletions if necessary, and traversing lists too
  if typeof obj is 'string' and typeof key is 'object'
    st = obj
    obj = key
    key = st
  if not obj? and this?.params?.key?
    obj = @copy @params
    key = obj.key
  key = key.split('.') if typeof key is 'string'
  try
    res = obj
    res = res[k] for k in key
    return res
  catch
    return undefined

P.flatten = (obj) ->
  obj ?= @params
  res = {}
  _flatten = (obj, key) ->
    for k of obj
      pk = if key then key + '.' + k else k
      v = obj[k]
      if typeof v is 'string'
        res[pk] = v
      else if Array.isArray v
        if typeof v[0] is 'object'
          for n of v
            await _flatten v[n], pk + '.' + n
        else
          res[pk] = v.join(', ')
      else
        await _flatten v, pk
  if Array.isArray obj
    results = []
    for d in data
      res = {}
      results.push await _flatten d
    return results
  else
    await _flatten obj
    return res

P.template = (content, vars) ->
  content ?= @params.content ? @params.template ? @body
  vars ?= @params
  if @params.url or content.startsWith 'http'
    content = await @fetch @params.url ? content
  if content.indexOf(' ') is -1 and content.indexOf('.') isnt -1 and content.length < 100
    try
      cs = await @_templates content
      content = cs.content
  ret = {}
  _rv = (obj, pre='') ->
    for o of obj
      ov = if pre then pre + '.' + o else o
      if typeof obj[o] is 'object' and not Array.isArray obj[o]
        _rv obj[o], pre + (if pre is '' then '' else '.') + o
      else if content.toLowerCase().indexOf('{{'+ov+'}}') isnt -1
        rg = new RegExp '{{'+ov+'}}', 'gi'
        content = content.replace rg, (if Array.isArray(obj[o]) then obj[o].join(', ') else (if typeof obj[o] is 'string' then obj[o] else (if obj[o] is true then 'Yes' else (if obj[o] is false then 'No' else ''))))
  _rv vars # replace all vars that are in the content
  kg = new RegExp '{{.*?}}', 'gi'
  if content.indexOf('{{') isnt -1 # retrieve any vars provided IN the content (e.g. a content template can specify a subject for an email to use)
    vs = ['subject','from','to','cc','bcc']
    # the could be vars in content that themselves contain vars, e.g {{subject I am the subject about {{id}} yes I am}}
    # and some of those vars may fail to get filled in. So define the list of possible vars names THEN go through the content with them
    for cp in content.toLowerCase().split '{{'
      pcp = cp.split('{{')[0].split('}}')[0].split(' ')[0]
      vs.push(pcp) if pcp not in vs
    for k in vs
      key = if content.toLowerCase().indexOf('{{'+k) isnt -1 then k else undefined
      if key
        keyu = if content.indexOf('{{'+key.toUpperCase()) isnt -1 then key.toUpperCase() else key
        val = content.split('{{'+keyu)[1]
        val = val.replace(kg,'') if val.split('}}')[0].indexOf('{{') # remove any vars present inside this one that were not able to have their values replaced
        val = val.split('}}')[0].trim()
        ret[key] = val if val
        kkg = new RegExp('{{'+keyu+'.*?}}','gi')
        content = content.replace(kkg,'')
  content = content.replace(kg, '') if content.indexOf('{{') isnt -1 # remove any outstanding vars in content that could not be replaced by provided vars
  ret.content = content
  # TODO consider if worth putting markdown formatting back in here, and how big a markdown parser is
  return ret # an obj of the content plus any vars found within the template

#P._templates = _index: true # an index to store templates in - although generally should be handled at the individual function/service level

P.device = () ->
  # make a simple device hash, not enough to uniquely identify a user, 
  # but useful for discerning user across devices, so can help user manage
  # login across devices and possibly identify unexpected usage
  # use user-agent and accept headers, possibly others, and could use geo-ip too (see server utilities file)
  res = {}
  try
    cf = @request.cf
    res.colo = cf.colo
    res.city = cf.city
    res.lat = cf.latitude
    res.lon = cf.longitude
  res.ip = @headers.ip
  res.country = @headers['cf-ipcountry']
  res.accept = @headers['accept']
  res['accept-language'] = @headers['accept-language']
  res['user-agent'] = @headers['user-agent']
  res['user-agent-hash'] = @hashhex @headers['user-agent'] #+ @headers['accept'] + @headers['accept-language']
  return res
P.device._cache = false

P.date = (rt, timed) ->
  rt ?= @params.date ? Date.now()
  timed ?= @params.time
  if typeof rt is 'number' or (typeof rt is 'string' and rt.indexOf(' ') is -1 and rt.indexOf('/') is -1 and rt.indexOf('-') is -1 and rt.length > 8 and rt.indexOf('T') is -1)
    try
      ret = new Date parseInt rt
      ret = ret.toISOString()
      return if timed then ret else ret.split('T')[0]
  try
    rt = rt.toString() if typeof rt is 'number'
    rt = rt[0] if Array.isArray(rt) and rt.length is 1 and Array.isArray rt[0]
    if typeof rt isnt 'string'
      try
        for k of rt
          rt[k] = '01' if typeof rt[k] not in ['number', 'string']
        rt = rt.join '-'
    rt = decodeURIComponent rt
    rt = rt.split('T')[0] if rt.indexOf('T') isnt -1
    rt = rt.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace /-(\d)$/, "-0$1"
    rt += '-01' if rt.indexOf('-') is -1
    pts = rt.split '-'
    if pts.length isnt 3
      rt += '-01' 
      pts = rt.split '-'
    rt = undefined if pts.length isnt 3
    rt = pts.reverse().join('-') if pts[0].length < pts[2].length
    return rt
  catch
    return undefined
P.date._cache = false

P.datetime = () -> return @date @params.datetime, @params.time ? true
P.datetime._cache = false
P.epoch = (epoch) ->
  epoch ?= @params.epoch
  epoch = epoch.toString() if typeof epoch is 'number'
  if not epoch
    return Date.now()
  else if epoch.startsWith('+') or epoch.startsWith('-') or (epoch.split('+').length is 2 and epoch.split('+')[0].length > 4) or (epoch.split('-').length is 2 and epoch.split('-')[0].length > 4)
    epoch = Date.now() + epoch if epoch.startsWith('+') or epoch.startsWith '-'
    if epoch.includes '+'
      [epoch, add] = epoch.replace('/', '').split '+'
      return (parseInt(epoch) + parseInt add).toString()
    else if epoch.includes '-'
      [epoch, subtract] = epoch.replace('/', '').split '-'
      return (parseInt(epoch) - parseInt subtract).toString()
  else if epoch.length > 8 and not epoch.includes('-') and not isNaN parseInt epoch
    return @date epoch, @params.time ? true
  else
    epoch += '-01' if epoch.length is 4
    epoch += '-01' if epoch.split('-').length < 3
    epoch += 'T' if epoch.indexOf('T') is -1
    epoch += '00:00' if epoch.indexOf(':') is -1
    epoch += ':00' if epoch.split(':').length < 3
    epoch += '.' if epoch.indexOf('.') is -1
    [start, end] = epoch.split('.')
    end = end.replace('Z','').replace('z','')
    end += '0' while end.length < 3
    end += 'Z' if end.indexOf('Z') is -1
    return new Date(start + '.' + end).valueOf()
P.epoch._cache = false

P._subroutes = (top) ->
  subroutes = []
  _lp = (p, n, _hide) =>
    for k of p
      if typeof p[k] in ['function', 'object']
        nd = (n ? '') + (if n then '.' else '') + k
        if not k.startsWith('_') and (typeof p[k] is 'function' or p[k]._index or p[k]._kv or p[k]._sheet) and not p[k]._hide and not p[k]._hides and not _hide and not nd.startsWith('scripts') and nd.indexOf('.scripts') is -1
          subroutes.push nd.replace /\./g, '/'
        _lp(p[k], nd, (_hide ? p[k]._hides)) if not Array.isArray(p[k]) and not k.startsWith '_'
  if top
    top = top.replace(/\//g, '.') if typeof top is 'string'
    _lp if typeof top is 'string' then @dot(P, top) else top
  return subroutes

'''
P.limit = (fn, ms=300) ->
  p = 0
  t = null

  lim = () ->
    n = Date.now()
    r = ms - (n - p)
    args = arguments
    if r <= 0 or r > ms
      if t
        clearTimeout t
        t = null
      p = n
      res = fn.apply this, args
    else
      t ?= setTimeout () =>
        p = Date.now()
        res = fn.apply this, args
      , r
    return res

  lim.stop = () -> clearTimeout t
  return lim
'''


'''
P.retry = (fn, params=[], opts={}) ->
  # params should be a list of params for the fn
  params = [params] if not Array.isArray params
  opts.retry ?= 3
  opts.pause ?= 500
  opts.increment ?= true
  # can provide a function in opts.check to check the result each time, and an opts.timeout to timeout each loop

  while opts.retry > 0
    res = undefined
    _wrap = () ->
      try
        res = await fn.apply this, params
    if typeof opts.timeout is 'number'
      await Promise.race [_wrap.call(this), P.sleep(opts.timeout)]
    else
      _wrap.call this
    if typeof opts.check is 'function'
      retry = await opts.check res, retry
      if retry is true
        return res
      else if retry is false
        retry -= 1
      else if typeof retry isnt 'number'
        retry = 0
    else if res? and res isnt false
      return res
    else
      retry -= 1

    if typeof opts.pause is 'number' and opts.pause isnt 0
      await P.sleep opts.pause
      if opts.increment is true
        opts.pause = opts.pause * 2
      else if typeof opts.increment is 'number'
        opts.pause += opts.increment
    
  return undefined

'''





P.passphrase = (len, lowercase) ->
  len ?= @params.passphrase ? @params.len ? 4
  lowercase ?= @params.lowercase ? @params.lower ? false
  words = []
  wl = P._passphrase_words.length
  while words.length < len
    w = P._passphrase_words[Math.floor((Math.random() * wl))]
    words.push if lowercase then w else w.substring(0,1).toUpperCase() + w.substring(1)
  return words.join ''
P.passphrase._cache = false

# the original xkcd password generator word list of 1949 common English words
# https://preshing.com/20110811/xkcd-password-generator/
# https://xkcd.com/936/
P._passphrase_words = ["ability","able","aboard","about","above","accept","accident","according",
"account","accurate","acres","across","act","action","active","activity",
"actual","actually","add","addition","additional","adjective","adult","adventure",
"advice","affect","afraid","after","afternoon","again","against","age",
"ago","agree","ahead","aid","air","airplane","alike","alive",
"all","allow","almost","alone","along","aloud","alphabet","already",
"also","although","am","among","amount","ancient","angle","angry",
"animal","announced","another","answer","ants","any","anybody","anyone",
"anything","anyway","anywhere","apart","apartment","appearance","apple","applied",
"appropriate","are","area","arm","army","around","arrange","arrangement",
"arrive","arrow","art","article","as","aside","ask","asleep",
"at","ate","atmosphere","atom","atomic","attached","attack","attempt",
"attention","audience","author","automobile","available","average","avoid","aware",
"away","baby","back","bad","badly","bag","balance","ball",
"balloon","band","bank","bar","bare","bark","barn","base",
"baseball","basic","basis","basket","bat","battle","be","bean",
"bear","beat","beautiful","beauty","became","because","become","becoming",
"bee","been","before","began","beginning","begun","behavior","behind",
"being","believed","bell","belong","below","belt","bend","beneath",
"bent","beside","best","bet","better","between","beyond","bicycle",
"bigger","biggest","bill","birds","birth","birthday","bit","bite",
"black","blank","blanket","blew","blind","block","blood","blow",
"blue","board","boat","body","bone","book","border","born",
"both","bottle","bottom","bound","bow","bowl","box","boy",
"brain","branch","brass","brave","bread","break","breakfast","breath",
"breathe","breathing","breeze","brick","bridge","brief","bright","bring",
"broad","broke","broken","brother","brought","brown","brush","buffalo",
"build","building","built","buried","burn","burst","bus","bush",
"business","busy","but","butter","buy","by","cabin","cage",
"cake","call","calm","came","camera","camp","can","canal",
"cannot","cap","capital","captain","captured","car","carbon","card",
"care","careful","carefully","carried","carry","case","cast","castle",
"cat","catch","cattle","caught","cause","cave","cell","cent",
"center","central","century","certain","certainly","chain","chair","chamber",
"chance","change","changing","chapter","character","characteristic","charge","chart",
"check","cheese","chemical","chest","chicken","chief","child","children",
"choice","choose","chose","chosen","church","circle","circus","citizen",
"city","class","classroom","claws","clay","clean","clear","clearly",
"climate","climb","clock","close","closely","closer","cloth","clothes",
"clothing","cloud","club","coach","coal","coast","coat","coffee",
"cold","collect","college","colony","color","column","combination","combine",
"come","comfortable","coming","command","common","community","company","compare",
"compass","complete","completely","complex","composed","composition","compound","concerned",
"condition","congress","connected","consider","consist","consonant","constantly","construction",
"contain","continent","continued","contrast","control","conversation","cook","cookies",
"cool","copper","copy","corn","corner","correct","correctly","cost",
"cotton","could","count","country","couple","courage","course","court",
"cover","cow","cowboy","crack","cream","create","creature","crew",
"crop","cross","crowd","cry","cup","curious","current","curve",
"customs","cut","cutting","daily","damage","dance","danger","dangerous",
"dark","darkness","date","daughter","dawn","day","dead","deal",
"dear","death","decide","declared","deep","deeply","deer","definition",
"degree","depend","depth","describe","desert","design","desk","detail",
"determine","develop","development","diagram","diameter","did","die","differ",
"difference","different","difficult","difficulty","dig","dinner","direct","direction",
"directly","dirt","dirty","disappear","discover","discovery","discuss","discussion",
"disease","dish","distance","distant","divide","division","do","doctor",
"does","dog","doing","doll","dollar","done","donkey","door",
"dot","double","doubt","down","dozen","draw","drawn","dream",
"dress","drew","dried","drink","drive","driven","driver","driving",
"drop","dropped","drove","dry","duck","due","dug","dull",
"during","dust","duty","each","eager","ear","earlier","early",
"earn","earth","easier","easily","east","easy","eat","eaten",
"edge","education","effect","effort","egg","eight","either","electric",
"electricity","element","elephant","eleven","else","empty","end","enemy",
"energy","engine","engineer","enjoy","enough","enter","entire","entirely",
"environment","equal","equally","equator","equipment","escape","especially","essential",
"establish","even","evening","event","eventually","ever","every","everybody",
"everyone","everything","everywhere","evidence","exact","exactly","examine","example",
"excellent","except","exchange","excited","excitement","exciting","exclaimed","exercise",
"exist","expect","experience","experiment","explain","explanation","explore","express",
"expression","extra","eye","face","facing","fact","factor","factory",
"failed","fair","fairly","fall","fallen","familiar","family","famous",
"far","farm","farmer","farther","fast","fastened","faster","fat",
"father","favorite","fear","feathers","feature","fed","feed","feel",
"feet","fell","fellow","felt","fence","few","fewer","field",
"fierce","fifteen","fifth","fifty","fight","fighting","figure","fill",
"film","final","finally","find","fine","finest","finger","finish",
"fire","fireplace","firm","first","fish","five","fix","flag",
"flame","flat","flew","flies","flight","floating","floor","flow",
"flower","fly","fog","folks","follow","food","foot","football",
"for","force","foreign","forest","forget","forgot","forgotten","form",
"former","fort","forth","forty","forward","fought","found","four",
"fourth","fox","frame","free","freedom","frequently","fresh","friend",
"friendly","frighten","frog","from","front","frozen","fruit","fuel",
"full","fully","fun","function","funny","fur","furniture","further",
"future","gain","game","garage","garden","gas","gasoline","gate",
"gather","gave","general","generally","gentle","gently","get","getting",
"giant","gift","girl","give","given","giving","glad","glass",
"globe","go","goes","gold","golden","gone","good","goose",
"got","government","grabbed","grade","gradually","grain","grandfather","grandmother",
"graph","grass","gravity","gray","great","greater","greatest","greatly",
"green","grew","ground","group","grow","grown","growth","guard",
"guess","guide","gulf","gun","habit","had","hair","half",
"halfway","hall","hand","handle","handsome","hang","happen","happened",
"happily","happy","harbor","hard","harder","hardly","has","hat",
"have","having","hay","he","headed","heading","health","heard",
"hearing","heart","heat","heavy","height","held","hello","help",
"helpful","her","herd","here","herself","hidden","hide","high",
"higher","highest","highway","hill","him","himself","his","history",
"hit","hold","hole","hollow","home","honor","hope","horn",
"horse","hospital","hot","hour","house","how","however","huge",
"human","hundred","hung","hungry","hunt","hunter","hurried","hurry",
"hurt","husband","ice","idea","identity","if","ill","image",
"imagine","immediately","importance","important","impossible","improve","in","inch",
"include","including","income","increase","indeed","independent","indicate","individual",
"industrial","industry","influence","information","inside","instance","instant","instead",
"instrument","interest","interior","into","introduced","invented","involved","iron",
"is","island","it","its","itself","jack","jar","jet",
"job","join","joined","journey","joy","judge","jump","jungle",
"just","keep","kept","key","kids","kill","kind","kitchen",
"knew","knife","know","knowledge","known","label","labor","lack",
"lady","laid","lake","lamp","land","language","large","larger",
"largest","last","late","later","laugh","law","lay","layers",
"lead","leader","leaf","learn","least","leather","leave","leaving",
"led","left","leg","length","lesson","let","letter","level",
"library","lie","life","lift","light","like","likely","limited",
"line","lion","lips","liquid","list","listen","little","live",
"living","load","local","locate","location","log","lonely","long",
"longer","look","loose","lose","loss","lost","lot","loud",
"love","lovely","low","lower","luck","lucky","lunch","lungs",
"lying","machine","machinery","mad","made","magic","magnet","mail",
"main","mainly","major","make","making","man","managed","manner",
"manufacturing","many","map","mark","market","married","mass","massage",
"master","material","mathematics","matter","may","maybe","me","meal",
"mean","means","meant","measure","meat","medicine","meet","melted",
"member","memory","men","mental","merely","met","metal","method",
"mice","middle","might","mighty","mile","military","milk","mill",
"mind","mine","minerals","minute","mirror","missing","mission","mistake",
"mix","mixture","model","modern","molecular","moment","money","monkey",
"month","mood","moon","more","morning","most","mostly","mother",
"motion","motor","mountain","mouse","mouth","move","movement","movie",
"moving","mud","muscle","music","musical","must","my","myself",
"mysterious","nails","name","nation","national","native","natural","naturally",
"nature","near","nearby","nearer","nearest","nearly","necessary","neck",
"needed","needle","needs","negative","neighbor","neighborhood","nervous","nest",
"never","new","news","newspaper","next","nice","night","nine",
"no","nobody","nodded","noise","none","noon","nor","north",
"nose","not","note","noted","nothing","notice","noun","now",
"number","numeral","nuts","object","observe","obtain","occasionally","occur",
"ocean","of","off","offer","office","officer","official","oil",
"old","older","oldest","on","once","one","only","onto",
"open","operation","opinion","opportunity","opposite","or","orange","orbit",
"order","ordinary","organization","organized","origin","original","other","ought",
"our","ourselves","out","outer","outline","outside","over","own",
"owner","oxygen","pack","package","page","paid","pain","paint",
"pair","palace","pale","pan","paper","paragraph","parallel","parent",
"park","part","particles","particular","particularly","partly","parts","party",
"pass","passage","past","path","pattern","pay","peace","pen",
"pencil","people","per","percent","perfect","perfectly","perhaps","period",
"person","personal","pet","phrase","physical","piano","pick","picture",
"pictured","pie","piece","pig","pile","pilot","pine","pink",
"pipe","pitch","place","plain","plan","plane","planet","planned",
"planning","plant","plastic","plate","plates","play","pleasant","please",
"pleasure","plenty","plural","plus","pocket","poem","poet","poetry",
"point","pole","police","policeman","political","pond","pony","pool",
"poor","popular","population","porch","port","position","positive","possible",
"possibly","post","pot","potatoes","pound","pour","powder","power",
"powerful","practical","practice","prepare","present","president","press","pressure",
"pretty","prevent","previous","price","pride","primitive","principal","principle",
"printed","private","prize","probably","problem","process","produce","product",
"production","program","progress","promised","proper","properly","property","protection",
"proud","prove","provide","public","pull","pupil","pure","purple",
"purpose","push","put","putting","quarter","queen","question","quick",
"quickly","quiet","quietly","quite","rabbit","race","radio","railroad",
"rain","raise","ran","ranch","range","rapidly","rate","rather",
"raw","rays","reach","read","reader","ready","real","realize",
"rear","reason","recall","receive","recent","recently","recognize","record",
"red","refer","refused","region","regular","related","relationship","religious",
"remain","remarkable","remember","remove","repeat","replace","replied","report",
"represent","require","research","respect","rest","result","return","review",
"rhyme","rhythm","rice","rich","ride","riding","right","ring",
"rise","rising","river","road","roar","rock","rocket","rocky",
"rod","roll","roof","room","root","rope","rose","rough",
"round","route","row","rubbed","rubber","rule","ruler","run",
"running","rush","sad","saddle","safe","safety","said","sail",
"sale","salmon","salt","same","sand","sang","sat","satellites",
"satisfied","save","saved","saw","say","scale","scared","scene",
"school","science","scientific","scientist","score","screen","sea","search",
"season","seat","second","secret","section","see","seed","seeing",
"seems","seen","seldom","select","selection","sell","send","sense",
"sent","sentence","separate","series","serious","serve","service","sets",
"setting","settle","settlers","seven","several","shade","shadow","shake",
"shaking","shall","shallow","shape","share","sharp","she","sheep",
"sheet","shelf","shells","shelter","shine","shinning","ship","shirt",
"shoe","shoot","shop","shore","short","shorter","shot","should",
"shoulder","shout","show","shown","shut","sick","sides","sight",
"sign","signal","silence","silent","silk","silly","silver","similar",
"simple","simplest","simply","since","sing","single","sink","sister",
"sit","sitting","situation","six","size","skill","skin","sky",
"slabs","slave","sleep","slept","slide","slight","slightly","slip",
"slipped","slope","slow","slowly","small","smaller","smallest","smell",
"smile","smoke","smooth","snake","snow","so","soap","social",
"society","soft","softly","soil","solar","sold","soldier","solid",
"solution","solve","some","somebody","somehow","someone","something","sometime",
"somewhere","son","song","soon","sort","sound","source","south",
"southern","space","speak","special","species","specific","speech","speed",
"spell","spend","spent","spider","spin","spirit","spite","split",
"spoken","sport","spread","spring","square","stage","stairs","stand",
"standard","star","stared","start","state","statement","station","stay",
"steady","steam","steel","steep","stems","step","stepped","stick",
"stiff","still","stock","stomach","stone","stood","stop","stopped",
"store","storm","story","stove","straight","strange","stranger","straw",
"stream","street","strength","stretch","strike","string","strip","strong",
"stronger","struck","structure","struggle","stuck","student","studied","studying",
"subject","substance","success","successful","such","sudden","suddenly","sugar",
"suggest","suit","sum","summer","sun","sunlight","supper","supply",
"support","suppose","sure","surface","surprise","surrounded","swam","sweet",
"swept","swim","swimming","swing","swung","syllable","symbol","system",
"table","tail","take","taken","tales","talk","tall","tank",
"tape","task","taste","taught","tax","tea","teach","teacher",
"team","tears","teeth","telephone","television","tell","temperature","ten",
"tent","term","terrible","test","than","thank","that","thee",
"them","themselves","then","theory","there","therefore","these","they",
"thick","thin","thing","think","third","thirty","this","those",
"thou","though","thought","thousand","thread","three","threw","throat",
"through","throughout","throw","thrown","thumb","thus","thy","tide",
"tie","tight","tightly","till","time","tin","tiny","tip",
"tired","title","to","tobacco","today","together","told","tomorrow",
"tone","tongue","tonight","too","took","tool","top","topic",
"torn","total","touch","toward","tower","town","toy","trace",
"track","trade","traffic","trail","train","transportation","trap","travel",
"treated","tree","triangle","tribe","trick","tried","trip","troops",
"tropical","trouble","truck","trunk","truth","try","tube","tune",
"turn","twelve","twenty","twice","two","type","typical","uncle",
"under","underline","understanding","unhappy","union","unit","universe","unknown",
"unless","until","unusual","up","upon","upper","upward","us",
"use","useful","using","usual","usually","valley","valuable","value",
"vapor","variety","various","vast","vegetable","verb","vertical","very",
"vessels","victory","view","village","visit","visitor","voice","volume",
"vote","vowel","voyage","wagon","wait","walk","wall","want",
"war","warm","warn","was","wash","waste","watch","water",
"wave","way","we","weak","wealth","wear","weather","week",
"weigh","weight","welcome","well","went","were","west","western",
"wet","whale","what","whatever","wheat","wheel","when","whenever",
"where","wherever","whether","which","while","whispered","whistle","white",
"who","whole","whom","whose","why","wide","widely","wife",
"wild","will","willing","win","wind","window","wing","winter",
"wire","wise","wish","with","within","without","wolf","women",
"won","wonder","wonderful","wood","wooden","wool","word","wore",
"work","worker","world","worried","worry","worse","worth","would",
"wrapped","write","writer","writing","written","wrong","wrote","yard",
"year","yellow","yes","yesterday","yet","you","young","younger",
"your","yourself","youth","zero","zoo"]