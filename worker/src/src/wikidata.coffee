
P.src.wikidata = (q) ->
  try q ?= @params.wikidata ? @params.q ? @params
  if typeof q is 'string'
    if q.indexOf('Q') is 0
      return @fetch 'https://dev.api.cottagelabs.com/use/wikidata/' + q
    else
      return @fetch 'https://dev.api.cottagelabs.com/use/wikidata?q=' + q
  else
    return @fetch 'https://dev.api.cottagelabs.com/use/wikidata', body: q


'''
P.src.wikidata = (qid) ->
  qid ?= @params.wikidata ? @params.url ? @params.wikipedia
  if typeof qid is 'string'
    if qid.includes 'wiki/'
      t = qid.split('wiki/').pop()
      qid = undefined
      try
        w = await @src.wikipedia.lookup {title: t}
        qid = w.data.pageprops.wikibase_item
    if qid
      res = await @fetch 'https://www.wikidata.org/wiki/Special:EntityData/' + qid + '.json'
      qid = res.entities[qid]
  if Array.isArray qid
    recs = []
    for q in qid
      recs.push await @src.wikidata._format q
    return recs
  else if typeof qid is 'object'
    return @src.wikidata._format qid
  else
    return

P.src.wikidata._index = settings: number_of_shards: 9
P.src.wikidata._prefix = false
'''

P.src.wikidata._format = (rec) ->
  #rec.type = rec.type # was this meant to come from somewhere else
  rec._id = rec.id
  rec.qid = rec.id
  rec.createdAt = Date.now()
  rec.label = rec.labels?.en?.value # is an english label required?
  delete rec.labels

  sl = {}
  for sw in (rec.sitelinks ? [])
    sl[sw] = rec.sitelinks[sw] if 'enwiki' in sw
  rec.sitelinks = sl

  rec.description = rec.descriptions?.en?.value
  delete rec.descriptions

  rec.alias = []
  for als in (rec.aliases ? [])
    rec.alias.push(al) for al in rec.aliases[als]
  delete rec.aliases

  rec.snaks = []
  for s in (rec.claims ? [])
    for sn in rec.claims[s]
      ds = await @src.wikidata.desnak sn.mainsnak
      rec.snaks.push(ds) if JSON.stringify(ds) isnt '{}'
      rec.image ?= ds.imgurl
  delete rec.claims

  try rec.wikipedia = rec.sitelinks?.enwiki?.url ? 'https://en.wikipedia.org/wiki/' + rec.sitelinks.enwiki.title.replace(/ /g,'_')
  try rec.wid = rec.sitelinks?.enwiki?.url.split('wiki/').pop()

  return rec


P.src.wikidata.desnak = (ms) ->
  ms ?= @params
  return {} if typeof ms isnt 'object' or not ms.datavalue?.value?

  snak = qualifiers: [], references: [], property: ms.property # like PS30
  try snak['key'] = (await @src.wikidata.property snak.property).label
  if typeof ms.datavalue.value isnt 'object'
    snak.value = ms.datavalue.value # an actual value
    snak.url = snak.value if ms.datatype is 'url'
  else if ms.datavalue.value.latitude
    snak.location = latitude: ms.datavalue.value.latitude, longitude: ms.datavalue.value.longitude, precision: ms.datavalue.value.precision
    snak.value = snak.location.latitude + (if snak.location.longitude then ',' + snak.location.longitude else '')
    snak.globe = ms.datavalue.value.globe.split('/').pop() if ms.datavalue.value.globe? # like Q2 is earth, could be dereferenced later
  else if ms.datavalue.value.amount
    snak[sk] = ms.datavalue.value[sk].toString() for sk in ['amount', 'upperBound', 'lowerBound']
    snak.value = snak.amount
    snak.unit = ms.datavalue.value.unit.split('/').pop() if ms.datavalue.value.unit # like Q712226 is square kilometer, later deref
  else if ms.datavalue.value.time
    snak[sk] = ms.datavalue.value[sk].toString() for sk in ['time', 'timezone', 'before', 'after', 'precision']
    snak.value = snak.time
  else if ms.datavalue.value.id
    snak.qid = ms.datavalue.value.id # like Q32, so needs later dereference and value set in snak.value (it would take too long and may run before the record to dereference exists anyway)
    #try
    #  v = await @src.wikidata snak.qid
    #  snak.value = v?.label

  for q in ms.qualifiers ? []
    for qk in ms.qualifiers[q]
      snak.qualifiers.push await @src.wikidata.desnak qk
  for r in ms.references ? []
    for skid in r['snaks-order']
      for ansk in r.snaks[skid]
        snak.references.push await @src.wikidata.desnak ansk

  if snak.key is 'image' or (typeof snak.value is 'string' and snak.value.toLowerCase().split('.').pop() in ['bmp', 'gif', 'jpg', 'jpeg', 'png', 'svg', 'tif', 'webp'])
    if snak.value.startsWith 'http'
      snak.imgurl = snak.value
    else
      snak.imgurl = 'https://upload.wikimedia.org/wikipedia/commons/'
      img = snak.value.replace /\s/g, '_'
      mds = crypto.createHash('md5').update(img, 'utf8').digest('hex') # base64
      snak.imgurl += mds.charAt(0) + '/' + mds.charAt(0) + mds.charAt(1) + '/' + encodeURIComponent img

  return if not snak.value and not snak.qid then {} else snak


_got_props = {}
P.src.wikidata.properties = () ->
  if not @refresh and JSON.stringify(_got_props) isnt '{}'
    return _got_props
  else
    _got_props = {}
    try
      if content = await @fetch 'https://www.wikidata.org/wiki/Wikidata:Database_reports/List_of_properties/all'
        tb = content.split('<table class="wikitable sortable">')[1].split('</table>')[0]
        rows = tb.split '</tr>'
        rows.shift() # the first row is headers
        for row in rows
          try
            prop = {}
            parts = row.split '</td>'
            try prop.pid = parts[0].replace('</a>', '').split('>').pop().trim().replace('\n', '')
            try prop.label = parts[1].replace('</a>', '').split('>').pop().trim().replace('\n', '')
            try prop.desc = parts[2].replace('</a>', '').split('>').pop().trim().replace('\n', '')
            try prop.alias = parts[3].replace('</a>', '').split('>').pop().replace(/, or/g, ',').replace(/, /g, ',').trim().replace('\n', '').split(',')
            try prop.type = parts[4].replace('</a>', '').split('>').pop().trim().replace('\n','')
            try prop.count = parts[5].replace('</a>', '').split('>').pop().replace(/,/g, '').trim().replace('\n', '')
            _got_props[prop.pid] = prop if typeof prop.pid is 'string' and prop.pid.length and prop.pid.startsWith 'P'
    return _got_props

P.src.wikidata.property = (prop) ->
  prop ?= @params.property
  return undefined if typeof prop isnt 'string'
  props = await @src.wikidata.properties()
  if props[prop]
    return props[prop]
  else
    q = prop.toLowerCase()
    qf = q.split(' ')[0]
    partials = []
    firsts = []
    for p of props
      pls = props[p].label.toLowerCase()
      if pls is q
        return props[p]
      else if pls.indexOf(q) isnt -1
        partials.push props[p]
      else if pls.indexOf(qf) isnt -1
        firsts.push props[p]
    return partials.concat firsts

P.src.wikidata.property.terms = (prop, size=100, counts=true, alphabetical=false) ->
  prop ?= @params.terms ? @params.property
  terms = {}
  loops = false
  key = false
  max = 0
  lp = 0
  sz = if size < 1000 then size else 1000
  qr = 'snaks.property.exact:' + prop
  while @keys(terms).length < size and (loops is false or lp < loops)
    res = await @src.wikidata {q: qr, size: sz, from: sz*lp}
    max = res.hits.total if res?.hits?.total?
    loops = if not res?.hits?.total? then 0 else Math.floor res.hits.total / sz
    for rec in res?.hits?.hits ? []
      for snak in rec._source?.snaks ? []
        if snak.property is prop
          key = snak.key if snak.key? and key is false
          if not snak.value? and snak.qid?
            qv = await @src.wikidata snak.qid
            snak.value = qv.label if qv?
          if snak.value?
            if not terms[snak.value]?
              terms[snak.value] = 0
              qr += ' AND NOT snaks.qid.exact:' + snak.qid if snak.qid? and qr.split('AND NOT').length < 100 #what is max amount of NOT terms?
            terms[snak.value] += 1
    lp += 1
  out = []
  out.push({term: t, count: terms[t]}) for t of terms
  if alphabetical
    out = out.sort (a,b) -> if a.term.toLowerCase().replace(/ /g,'') > b.term.toLowerCase().replace(/ /g,'') then 1 else -1
  else
    out = out.sort (a,b) -> if b.count > a.count then 1 else -1
  return if counts then {property: key, total: max, terms: out} else out.map x => x.term


# NOTE newer improved ROR data and dumps have GRID and ROR in them as well, so this is only needed if full ROR isn't easily available locally
P.src.wikidata.grid2ror = (grid, wd) ->
  wd = await @src.wikidata(wd) if typeof wd is 'string'
  wd ?= await @src.wikidata '(snaks.property:"P6782" OR snaks.property:"P1366") AND snaks.property:"P2427" AND snaks.value:"' + grid + '"'
  if typeof wd is 'object' and wd.snaks?
    for s in wd.snaks
      if s.property is 'P6782'
        return s.value
      if s.property is 'P1366' and s.qid
        return @src.wikidata.grid2ror grid, s.qid
  return


P.src.wikidata._flatten = (rec) ->
  res = {}
  for c in rec.snaks
    if not c.value and c.qid
      c.value = (await @src.wikidata _c.qid).label
    if not c.value and c.property
      c.value = (await @src.wikidata.property c).label
    if res[c.key]
      res[c.key] = [res[c.key]] if not Array.isArray res[c.key]
      res[c.key].push c.value
    else
      res[c.key] = c.value
  return res


'''
API.use.wikidata.snakalyse = (snaks) ->
  res = {meta: {}, total: 0, person: 0, orgs: 0, locs: 0, keys: []}
  rec = {}
  if typeof snaks is 'object' and snaks.snaks?
    rec = snaks
    snaks = snaks.snaks 
  return res if not snaks?
  snaks = [snaks] if not _.isArray snaks
  seen = []
  hascountry = false
  hasviaf = false
  hassex = false
  hasfamily = false
  for snak in snaks
    if snak.key
      res.keys.push(snak.key) if snak.key not in res.keys
      res.total += 1
      if snak.key + '_' + snak.value not in seen
        seen.push snak.key + '_' + snak.value
        tsk = snak.key.replace(/ /g,'_')
        hascountry = true if snak.key is 'country'
        hasviaf = true if snak.key is 'VIAF ID'
        hassex = true if snak.key is 'sex or gender'
        hasfamily = true if snak.key is 'family name'

        if tsk.length and (snak.key in _props.research or snak.key in ['MeSH code','MeSH descriptor ID','MeSH term ID','MeSH concept ID',
            'ICD-9-CM','ICD-9','ICD-10','ICD-10-CM',
            'ICTV virus ID','ICTV virus genome composition',
            'IUCN taxon ID','NCBI taxonomy ID'
            'DiseasesDB','GARD rare disease ID',
            "UniProt protein ID","RefSeq protein ID","Ensembl protein ID","Ensembl transcript ID",
            "HGNC gene symbol","Gene Atlas Image","GeneReviews ID",
            "Genetics Home Reference Conditions ID","FAO 2007 genetic resource ID","GeneDB ID","Gene Ontology ID","Ensembl gene ID",
            "Entrez Gene ID","HomoloGene ID",
            "InChIKey","InChI",
            'Dewey Decimal Classification','Library of Congress Classification',
            "AICS Chemical ID","MassBank accession ID",'ChEMBL ID',
            'LiverTox ID'
          ])
          res.meta[tsk] = [] if not _.isArray res.meta[tsk] 
          res.meta[tsk].push {value: snak.value, qid: snak.qid}

        if snak.key in ['AICS Chemical ID','ChEMBL ID','chemical formula','chemical structure',"MassBank accession ID"] or snak.qid in ['Q11173'] # chemical compound
          res.meta.chemical = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('chemical') if 'chemical' not in res.meta.what

        if snak.key in ['ICTV virus ID','ICTV virus genome composition','has natural reservoir'] or snak.key is 'instance of' and snak.value is 'strain'
          res.meta.virus = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('virus') if 'virus' not in res.meta.what

        if snak.key in ['DrugBank ID','significant drug interaction']
          res.meta.drug = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('drug') if 'drug' not in res.meta.what

        if snak.key in ['LiverTox ID','eMedicine ID','medical condition treated','European Medicines Agency product number'] or (snak.key is 'instance of' and snak.qid in ['Q12140','Q35456']) # medication, essential medicine
          res.meta.medicine = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('medicine') if 'medicine' not in res.meta.what

        if snak.key in ['GARD rare disease ID','DiseasesDB','drug used for treatment','symptoms','ICD-9','ICD-10']
          res.meta.disease = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('disease') if 'disease' not in res.meta.what

        if snak.key in ["UniProt protein ID","RefSeq protein ID","Ensembl protein ID"]
          res.meta.protein = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('protein') if 'protein' not in res.meta.what

        if snak.key in ["HGNC gene symbol","Gene Atlas Image","GeneReviews ID","Genetics Home Reference Conditions ID","FAO 2007 genetic resource ID",
            "GeneDB ID","Gene Ontology ID","Ensembl gene ID","Ensembl transcript ID","Entrez Gene ID","HomoloGene ID"]
          res.meta.gene = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('gene') if 'gene' not in res.meta.what

        if snak.key in _props.organisation or (snak.key is 'instance of' and ((typeof snak.value is 'string' and snak.value.toLowerCase().indexOf('company') isnt -1) or snak.qid in ['Q31855'])) # research institute
          res.orgs += 1
          res.meta.organisation = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('organisation') if 'organisation' not in res.meta.what
        else if snak.key in _props.location or (snak.key is 'instance of' and snak.qid in [
          'Q3624078','Q123480','Q170156','Q687554','Q43702','Q206696','Q6256']) # sovereign state, landlocked country, confederation, Federal Treaty, federal state, Helvetic Republic, country
          res.locs += 1
          res.meta.place = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('place') if 'place' not in res.meta.what

        if snak.key is 'CBDB ID' or (snak.key is 'instance of' and snak.qid is 'Q5') # human
          res.person += 1
          res.meta.person = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('person') if 'person' not in res.meta.what

        if snak.location
          res.meta.location = snak.location

  if hasviaf and hascountry and not res.meta.place? # to try to avoid other things that have country, but things other than places have viaf too - this may not work if people often have viaf and country
    res.locs += 1
    res.meta.place = rec.label ? true
    res.meta.what ?= []
    res.meta.what.push('place') if 'place' not in res.meta.what
  if hassex and hasfamily and not res.meta.person?
    res.person += 1
    res.meta.person = rec.label ? true
    res.meta.what ?= []
    res.meta.what.push('person') if 'person' not in res.meta.what
  if res.meta.what? and 'organisation' in res.meta.what and 'place' in res.meta.what
    delete res.meta.place if res.meta.place?
    res.meta.what = _.without res.meta.what, 'place'
  if res.meta.what? and 'disease' in res.meta.what
    delete res.meta.medicine if res.meta.medicine?
    delete res.meta.drug if res.meta.drug?
    res.meta.what = _.without(res.meta.what, 'medicine') if 'medicine' in res.meta.what
    res.meta.what = _.without(res.meta.what, 'drug') if 'drug' in res.meta.what
  return res

_props = {
  #ORGANISATION
  organisation: [
    "headquarters location",
    "subsidiary",
    "typically sells",
    "Merchant Category Code",
    #"industry",
    "parent organization"
    #"Ringgold ID" - locations have ringgold IDs too :(
  ],

  #LOCATION
  location: [
    "diplomatic relation",
    "M.49 code",
    "capital of",
    "postal code",
    "local dialing code",
    "locator map image",
    "shares border with",
    "coordinate location",
    "located on terrain feature",
    "detail map",
    "located in time zone",
    "continent",
    "lowest point",
    "highest point",
    "location map",
    "relief location map",
    "coordinates of easternmost point",
    "coordinates of westernmost point",
    "coordinates of northernmost point",
    "coordinates of southernmost point",
    "located in the administrative territorial entity",
    "China administrative division code",
    "UIC numerical country code",
    "UIC alphabetical country code",
    "coat of arms image",
    #"country",
    "head of government",
    "GS1 country code",
    "country calling code",
    "language used",
    "currency",
    "capital",
    "office held by head of state",
    "head of state",
    "flag",
    "flag image",
    "official language",
    "contains administrative territorial entity",
    "mobile country code",
    "INSEE countries and foreign territories code"
  ],
  
  #SOURCES
  sources: [
    "Google Knowledge Graph ID",
    "Microsoft Academic ID",
    "BBC Things ID",
    "Getty AAT ID",
    "Quora topic ID",
    
    "image",
    "subreddit",
  
    "PhilPapers topic",
  
    "Wikitribune category",
    "New York Times topic ID",
    "The Independent topic ID",
    "Google News topics ID",
    "IPTC NewsCode",
    "Guardian topic ID",
  
    "Library of Congress Control Number (LCCN) (bibliographic)",
    "Library of Congress Classification",
    "Library of Congress authority ID",
    "LoC and MARC vocabularies ID",
  
    "Encyclopedia of Life ID",
    "Encyclopædia Britannica Online ID",
    "Encyclopædia Universalis ID",
    "Encyclopedia of Modern Ukraine ID",
    "Stanford Encyclopedia of Philosophy ID",
    "Canadian Encyclopedia article ID",
    "Cambridge Encyclopedia of Anthropology ID",
    "Great Aragonese Encyclopedia ID",
    "Orthodox Encyclopedia ID",
    "Treccani's Enciclopedia Italiana ID",
    "Gran Enciclopèdia Catalana ID",
  
    "Danish Bibliometric Research Indicator level",
    "Danish Bibliometric Research Indicator (BFI) SNO/CNO",
    "Biblioteca Nacional de España ID",
    "Finnish national bibliography corporate name ID",
    "Libraries Australia ID",
    "Bibliothèque nationale de France ID",
    "National Library of Brazil ID",
    "Shanghai Library place ID",
    "National Library of Greece ID",
    "Portuguese National Library ID",
    "National Library of Iceland ID",
    "National Library of Israel ID",
    "Open Library ID",
    "Open Library subject ID",
  
    "OpenCitations bibliographic resource ID",
  
    "UNESCO Thesaurus ID",
    "ASC Leiden Thesaurus ID",
    "BNCF Thesaurus ID",
    "NCI Thesaurus ID",
    "STW Thesaurus for Economics ID",
    "Thesaurus For Graphic Materials ID",
    "UK Parliament thesaurus ID",
  
    "Wolfram Language entity type",
    "Wolfram Language unit code",
    "Wolfram Language entity code",
  
    "OmegaWiki Defined Meaning"
  ],

  #RESEARCH
  research: [
    "taxonomic type",
    "taxon name",
    "taxon rank",
    "parent taxon",
    "found in taxon",
    "taxon synonym",
    "this taxon is source of",
    "taxon range map image",
  
    "biological process",
    "ortholog",
    "strand orientation",
    "cytogenetic location",
    "chromosome",
    "genomic start",
    "genomic end",
    "cell component",
    "element symbol",
    "encodes",
    "significant drug interaction",
    "molecular function",
    "possible medical findings",
    "health specialty",
    "chemical formula",
    "chemical structure",
    "physically interacts with",
    "active ingredient in",
    "therapeutic area",
    "afflicts",
    "defining formula",
    "measured by",
    "vaccine for",
    "introduced feature",
    "has contributing factor",
    "has active ingredient",
    "has natural reservoir",
    "anatomical location",
    "development of anatomical structure",
    "medical condition treated",
    "arterial supply",
    "venous drainage",
    "pathogen transmission process",
    "risk factor",
    "possible treatment",
    "drug used for treatment",
    "medical examinations",
    "genetic association",
    "symptoms",
    "encoded by",
    #"location",
    "connects with",
    "property constraint",
    "instance of",
    "subclass of",
    "does not have part",
    "has cause",
    "subject has role",
    "has quality",
    "has part",
    "has effect",
    "has immediate cause",
    "has parts of the class",
    "part of",
    "opposite of",
    "facet of",
    "natural reservoir of",
    "equivalent property",
    "partially coincident with",
    "equivalent class",
    "said to be the same as",
    "properties for this type",
    "used by",
    "Commons category",
    "route of administration"
  ],

  #IDS
  ids: [
    "MeSH code",
    "MeSH descriptor ID",
    "MeSH term ID",
    "MeSH concept ID",
  
    "ICD-9-CM",
    "ICD-9",
    "ICD-10",
    "ICD-10-CM",
    "ICD-11 (foundation)",
  
    "ICTV virus ID",
    "ICTV virus genome composition",
  
    "iNaturalist taxon ID",
    "ADW taxon ID",
    "BioLib taxon ID",
    "Fossilworks taxon ID",
    "IUCN taxon ID",
    "NCBI taxonomy ID",
  
    "NCBI locus tag",
    "IUCN conservation status",
    "Dewey Decimal Classification",
    "DiseasesDB",
    "GeoNames feature code",
    "GeoNames ID",
    "ITU letter code",
    "MSW ID",
    "NBN System Key",
    "EPPO Code",
    "SPLASH",
    "isomeric SMILES",
    "canonical SMILES",
    "InChIKey",
    "InChI",
    "NSC number",
    "Reaxys registry number",
    "European Medicines Agency product number",
    "OCLC control number",
    "CosIng number",
    "Gmelin number",
    "EC enzyme number",
    "ZVG number",
    "MCN code",
    "Kemler code",
    "GenBank Assembly accession",
    "NUTS code",
    "EC number",
    "CAS Registry Number",
    "ATC code",
    "MathWorld identifier",
    "UNSPSC Code",
    "IPA transcription",
    "ISNI",
  
    "ISO 3166-2 code",
    "ISO 4 abbreviation",
    "ISO 3166-1 numeric code",
    "ISO 3166-1 alpha-3 code",
    "ISO 3166-1 alpha-2 code",
    "ITU/ISO/IEC object identifier",
    "U.S. National Archives Identifier",
  
    "IRMNG ID",
    "Global Biodiversity Information Facility ID",
    "Human Phenotype Ontology ID",
    "Freebase ID",
    "YSA ID",
    "PersonalData.IO ID",
    "BabelNet ID",
    "Klexikon article ID",
    "EuroVoc ID",
    "JSTOR topic ID",
    "Semantic Scholar author ID",
    "GND ID",
    "PSH ID",
    "YSO ID",
    "HDS ID",
    "Disease Ontology ID",
    "Elhuyar ZTH ID",
    "MonDO ID",
    "ORCID iD",
    "WorldCat Identities ID",
    "VIAF ID",
    "archINFORM location ID",
    "Pleiades ID",
    "Nomisma ID",
    "GACS ID",
    "NE.se ID",
    "FAST ID",
    "GARD rare disease ID",
    "MedlinePlus ID",
    "Dagens Nyheter topic ID",
    "DMOZ ID",
    "Analysis &amp; Policy Observatory term ID",
    "DR topic ID",
    "ICPC 2 ID",
    "OMIM ID",
    "Store medisinske leksikon ID",
    "NHS Health A to Z ID",
    "Patientplus ID",
    "eMedicine ID",
    "BHL Page ID",
    "Invasive Species Compendium Datasheet ID",
    "OSM relation ID",
    "GeoNLP ID",
    "Zhihu topic ID",
    "Observation.org ID",
    "IUPAC Gold Book ID",
    "Dyntaxa ID",
    "New Zealand Organisms Register ID",
    "Fauna Europaea New ID",
    "Fauna Europaea ID",
    "Belgian Species List ID",
    "TDKIV term ID",
    "Foundational Model of Anatomy ID",
    "UBERON ID",
    "NSK ID",
    "CANTIC ID",
    "NALT ID",
    "WoRMS-ID for taxa",
  
    "Crossref funder ID",
    "RoMEO publisher ID",
    "NORAF ID",
    "GRID ID",
    "CONOR ID",
    "Publons publisher ID",
    "SHARE Catalogue author ID",
    "NUKAT ID",
    "EGAXA ID",
    "ULAN ID",
    "ROR ID",
    "HAL structure ID",
    "ELNET ID",
    "TA98 Latin term",
    "Terminologia Anatomica 98 ID",
    "GPnotebook ID",
    "archINFORM keyword ID",
    "FOIH heritage types ID",
    "ILI ID",
    "Römpp online ID",
    "Pfam ID",
    "ECHA InfoCard ID",
    "MassBank accession ID",
    "ChEBI ID",
    "NDF-RT ID",
    "Guide to Pharmacology Ligand ID",
    "ChEMBL ID",
    "ChemSpider ID",
    "PubChem CID",
    "KEGG ID",
    "DSSTox substance ID",
    "CA PROP 65 ID",
    "IEDB Epitope ID",
    "PDB ligand ID",
    "DrugBank ID",
    "PDB structure ID",
    "LiverTox ID",
    "RxNorm ID",
    "Rosetta Code ID",
    "UniProt journal ID",
    "NLM Unique ID",
    "Scopus Source ID",
    "JUFO ID",
    "Human Metabolome Database ID",
    "NIAID ChemDB ID",
    "KNApSAcK ID",
    "Joconde inscription ID",
    "BIDICAM authority ID",
    "BVPH authority ID",
    "LEM ID",
    "ICSC ID",
    "MinDat mineral ID",
    "AICS Chemical ID",
    "Reactome ID",
    "Xenopus Anatomical Ontology ID",
    "ARKive ID",
    "CITES Species+ ID",
    "UniProt protein ID",
    "RefSeq protein ID",
    "Ensembl protein ID",
    "HGNC gene symbol",
    "Gene Atlas Image",
    "GeneReviews ID",
    "Genetics Home Reference Conditions ID",
    "FAO 2007 genetic resource ID",
    "GeneDB ID",
    "Gene Ontology ID",
    "Ensembl gene ID",
    "Ensembl transcript ID",
    "Entrez Gene ID",
    "HomoloGene ID",
    "Pschyrembel Online ID",
    "HCIS ID",
    "BMRB ID",
    "ZINC ID",
    "HSDB ID",
    "3DMet ID",
    "SpectraBase compound ID",
    "GTAA ID",
    "HGNC ID",
    "RefSeq RNA ID",
    "History of Modern Biomedicine ID",
    "Gynopedia ID",
    "De Agostini ID",
    "ESCO skill ID",
    "ANZSRC FoR ID",
    "Spider Ontology ID",
    "Coflein ID",
    "SAGE journal ID",
    "ERA Journal ID",
    "NIOSHTIC-2 ID",
    "ISOCAT id"
  ]
}

'''