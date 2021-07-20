
P.tdm = {}

P.tdm.occurrence = (content, sub, overlap) ->
	content ?= this?.params?.content ? this?.params?.url
	content = @fetch(content) if content.indexOf('http') is 0
	sub ?= this?.params?.sub ? this?.params?.q
	overlap ?= this?.params?.overlap
	content += ""
	sub += ""
	return (content.length + 1) if sub.length <= 0
	n = 0
	pos = 0
	step = if overlap then 1 else sub.length
	while true
		pos = content.indexOf sub, pos
		if pos >= 0
			++n
			pos += step
		else break
	return n

P.tdm.levenshtein = (a, b, lowercase) ->
	a ?= this?.params?.a
	b ?= this?.params?.b
	lowercase ?= this?.params?.lowercase ? true
	if lowercase
		a = a.toLowerCase()
		b = b.toLowerCase()
	minimator = (x, y, z) ->
		return x if x <= y and x <= z
		return y if y <= x and y <= z
		return z

	m = a.length
	n = b.length

	if m < n
		c = a
		a = b
		b = c
		o = m
		m = n
		n = o

	r = [[]]
	c = 0
	while c < n + 1
		r[0][c] = c
		c++

	i = 1
	while i < m + 1
		r[i] = [i]
		j = 1
		while j < n + 1
			cost = if a.charAt( i - 1 ) is b.charAt( j - 1 ) then 0 else 1
			r[i][j] = minimator( r[i-1][j] + 1, r[i][j-1] + 1, r[i-1][j-1] + cost )
			j++
		i++

	return distance: r[ r.length - 1 ][ r[ r.length - 1 ].length - 1 ], length: {a:m, b:n} #, detail: r

# https://en.wikipedia.org/wiki/Hamming_distance#Algorithm_example
# this is faster than levenshtein but not always so useful
# this works slightly better with perceptual hashes, or anything where just need to know how many changes to make to become the same
# for example the levenshtein difference between 1234567890 and 0123456789 is 2
# whereas the hamming distance is 10
P.tdm.hamming = (a, b, lowercase) ->
	a ?= this?.params?.a
	b ?= this?.params?.b
	lowercase ?= this?.params?.lowercase ? true
	if lowercase
		a = a.toLowerCase()
		b = b.toLowerCase()
	if a.length < b.length
		short = a
		long = b
	else
		short = b
		long = a
	pos = long.indexOf short
	ss = short.split('')
	sl = long.split('')
	if sl.length > ss.length
		diff = sl.length - ss.length
		if 0 < pos
			pc = 0
			while pc < pos
				ss.unshift ''
				pc++
				diff--
		c = 0
		while c < diff
			ss.push ''
			c++
	moves = 0
	for k of sl
		moves++ if ss[k] isnt sl[k]
	return moves

P.tdm.extract = (opts) ->
	# opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
	#opts ?= @params
	if opts.url and not opts.content
		if opts.url.indexOf('.pdf') isnt -1 or opts.url.indexOf('/pdf') isnt -1
			opts.convert ?= 'pdf'
		else
			opts.content = await @puppet opts.url
	if opts.convert
		try
			text = await @convert[opts.convert + '2txt'] opts.url ? opts.content
	text ?= opts.content

	opts.matchers ?= [opts.match]
	if opts.start?
		parts = text.split opts.start
		text = if parts.length > 1 then parts[1] else parts[0]
	text = text.split(opts.end)[0] if opts.end?
	text = text.toLowerCase() if opts.lowercase
	text = text.replace(/[^a-z0-9]/g,'') if opts.ascii
	text = text.replace(/ /g,'') if opts.spaces is false

	res = {length: text.length, matched: 0, matches: [], matchers: opts.matchers, text: text}

	if text and typeof text isnt 'number'
		for match in (if typeof opts.matchers is 'string' then opts.matchers.split(',') else opts.matchers)
			if typeof match is 'string'
				mopts = ''
				if match.indexOf('/') is 0
					lastslash = match.lastIndexOf '/'
					if lastslash+1 isnt match.length
						mopts = match.substring lastslash+1
						match = match.substring 1,lastslash
				else
					match = match.replace /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&"
			else
				mopts = ''
			mopts += 'i' if opts.lowercase
			try
				mr = new RegExp match, mopts
				if m = mr.exec text
					res.matched += 1
					res.matches.push {matched: match.toString(), result: m}

	return res

P.tdm.emails = (opts={}) ->
	opts.matchers = ['/([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi','/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi']
	emails = []
	checked = []
	ex = P.tdm.extract opts
	for pm in ex.matches
		for pmr in pm.result
			if pmr not in checked
				emails.push(pmr) if typeof P.mail?.validate? isnt 'function' or P.mail.validate(pmr, P.settings.service?.openaccessbutton?.mail?.pubkey).is_valid
			checked.push pmr
	return emails

P.tdm.stopwords = (stops, more, gramstops=true) -> 
	# removed wordpos option from this
	stops ?= ['purl','w3','http','https','ref','html','www','ref','cite','url','title','date','nbsp','doi','fig','figure','supplemental',
		'year','time','january','february','march','april','may','june','july','august','september','october','november','december',
		'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec','keywords','revised','accepted','file','attribution',
		'org','com','id','wp','main','website','blogs','media','people','years','made','location','its','asterisk','called','xp','er'
		'image','jpeg','jpg','png','php','object','false','true','article','chapter','book','caps','isbn','scale','axis','accessed','email','e-mail',
		'story','first1','first2','last1','last2','general','list','accessdate','view_news','d0','dq','sfnref','onepage','sfn','authorlink']
	gramstops = ["apos", "as", "able", "about", "above", "according", "accordingly", "across", "actually", "after", "afterwards", 
		"again", "against", "aint", "all", "allow", "allows", "almost", "alone", "along", "already", "also", "although", "always", "am", 
		"among", "amongst", "an", "and", "another", "any", "anybody", "anyhow", "anyone", "anything", "anyway", "anyways", "anywhere", 
		"apart", "appear", "appreciate", "appropriate", "are", "arent", "around", "as", "aside", "ask", "asking", "associated", "at", 
		"available", "away", "awfully", "be", "became", "because", "become", "becomes", "becoming", "been", "before", "beforehand", 
		"behind", "being", "believe", "below", "beside", "besides", "best", "better", "between", "beyond", "both", "brief", "but", "by", 
		"cmon", "cs", "came", "can", "cant", "cannot", "cant", "cause", "causes", "certain", "certainly", "changes", "clearly", "co", 
		"com", "come", "comes", "concerning", "consequently", "consider", "considering", "contain", "containing", "contains", "corresponding", 
		"could", "couldnt", "course", "currently", "definitely", "described", "despite", "did", "didnt", "different", "do", "does", "doesnt", 
		"doing", "dont", "done", "down", "downwards", "during", "each", "edu", "eg", "eight", "either", "else", "elsewhere", "enough", "entirely", 
		"especially", "et", "etc", "even", "ever", "every", "everybody", "everyone", "everything", "everywhere", "ex", "exactly", "example", "except", 
		"far", "few", "fifth", "first", "five", "followed", "following", "follows", "for", "former", "formerly", "forth", "four", "from", "further", 
		"furthermore", "get", "gets", "getting", "given", "gives", "go", "goes", "going", "gone", "got", "gotten", "greetings", "had", "hadnt", 
		"happens", "hardly", "has", "hasnt", "have", "havent", "having", "he", "hes", "hello", "help", "hence", "her", "here", "heres", "hereafter", 
		"hereby", "herein", "hereupon", "hers", "herself", "hi", "him", "himself", "his", "hither", "hopefully", "how", "howbeit", "however", "i", "I", 
		"id", "ill", "im", "ive", "ie", "if", "ignored", "immediate", "in", "inasmuch", "inc", "indeed", "indicate", "indicated", "indicates", "
		inner", "insofar", "instead", "into", "inward", "is", "isnt", "it", "itd", "itll", "its", "itself", "just", "keep", "keeps", "kept", 
		"know", "knows", "known", "last", "lately", "later", "latter", "latterly", "least", "less", "lest", "let", "lets", "like", "liked", "likely", 
		"little", "look", "looking", "looks", "ltd", "mainly", "many", "may", "maybe", "me", "mean", "meanwhile", "merely", "might", "more", "moreover", 
		"most", "mostly", "much", "must", "my", "myself", "name", "namely", "nd", "near", "nearly", "necessary", "need", "needs", "neither", "never", 
		"nevertheless", "new", "next", "nine", "no", "nobody", "non", "none", "noone", "nor", "normally", "not", "nothing", "now", "nowhere", 
		"obviously", "of", "off", "often", "oh", "ok", "okay", "old", "on", "once", "one", "ones", "only", "onto", "or", "other", "others", "otherwise", 
		"ought", "our", "ours", "ourselves", "out", "outside", "over", "overall", "own", "particular", "particularly", "per", "perhaps", "placed", 
		"please", "plus", "possible", "presumably", "probably", "provides", "que", "quite", "qv", "rather", "rd", "re", "really", "reasonably", 
		"regarding", "regardless", "regards", "relatively", "respectively", "right", "said", "same", "saw", "say", "saying", "says", "second", 
		"secondly", "see", "seeing", "seem", "seemed", "seeming", "seems", "seen", "self", "selves", "sensible", "sent", "serious", "seriously", 
		"seven", "several", "shall", "she", "should", "shouldnt", "since", "six", "so", "some", "somebody", "somehow", "someone", "something", 
		"sometime", "sometimes", "somewhat", "somewhere", "soon", "sorry", "specified", "specify", "specifying", "still", "sub", "such", "sup", "sure", 
		"ts", "take", "taken", "tell", "tends", "th", "than", "thank", "thanks", "thanx", "that", "thats", "thats", "the", "their", "theirs", "them", 
		"themselves", "then", "thence", "there", "theres", "thereafter", "thereby", "therefore", "therein", "theres", "thereupon", "these", "they", 
		"theyd", "theyll", "theyre", "theyve", "think", "third", "this", "thorough", "thoroughly", "those", "though", "three", "through", 
		"throughout", "thru", "thus", "to", "together", "too", "took", "toward", "towards", "tried", "tries", "truly", "try", "trying", "twice", 
		"two", "un", "under", "unfortunately", "unless", "unlikely", "until", "unto", "up", "upon", "us", "use", "used", "useful", "uses", "using", 
		"usually", "value", "various", "very", "via", "viz", "vs", "want", "wants", "was", "wasnt", "way", "we", "wed", "well", "weve", 
		"welcome", "well", "went", "were", "werent", "what", "whats", "whatever", "when", "whence", "whenever", "where", "wheres", "whereafter", 
		"whereas", "whereby", "wherein", "whereupon", "wherever", "whether", "which", "while", "whither", "who", "whos", "whoever", "whole", "whom", 
		"whose", "why", "will", "willing", "wish", "with", "within", "without", "wont", "wonder", "would", "would", "wouldnt", "yes", "yet", "you", 
		"youd", "youll", "youre", "youve", "your", "yours", "yourself", "yourselves", "zero"]
	if gramstops
		for g in gramstops
			stops.push(g) if g not in stops
	if more
		more = more.split(',') if typeof more is 'string'
		for m in more
			stops.push(m) if m not in stops
	return stops

# note that new wordpos can be used in browser and can preload word files or get them on demand
# try this from within CF and see if it works fast enough - it'll be about 7MB compressed data to 
# preload all, or on demand may introduce some lag
# https://github.com/moos/wordpos-web
