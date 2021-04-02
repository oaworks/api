
import moment from 'moment'
import { Random } from 'meteor/random'

API.oai = {}
API.oai.pmh = {}

API.add 'oai',
  get: () ->
    verb = if this.queryParams.verb? then this.queryParams.verb.toLowerCase() else false
    if verb is 'identify'
      res = API.oai.pmh.identify 'https://' + this.request.headers.host + '/oai'
    else if verb is 'listsets'
      res = API.oai.pmh.sets 'https://' + this.request.headers.host + '/oai'
    else if verb is 'listmetadataformats'
      res = API.oai.pmh.formats 'https://' + this.request.headers.host + '/oai'
    else if verb is 'listrecords'
      res = API.oai.pmh.records 'https://' + this.request.headers.host + '/oai'
    else if verb is 'listidentifiers'
      res = API.oai.pmh.identifiers 'https://' + this.request.headers.host + '/oai'
    else
      res = API.oai.pmh.bad 'verb', 'https://' + this.request.headers.host + '/oai'
      
    return
      statusCode: 200 # oai-pmh seems to just return errors as 200 but with the error info in the xml. The only difference is can return a 503 if temporarily unavailable, with a retry-after period specified
      headers: {'Content-Type': 'application/xml'}
      body: res



API.oai.pmh.identify = (endpoint='https://api.lvatn.com/oai', name='Leviathan Journal', email='sysadmin@cottagelabs.com') ->
  earliestDatestamp = '2017-12-11T13:38:19Z' # get this from whatever index is being listed, earliest record in it
  granularity = 'YYYY-MM-DDThh:mm:ssZ' # what are the options? why is it so granular in doaj?
  deletedRecord = 'transient' # what is this?
  return '\
<OAI-PMH xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.openarchives.org/OAI/2.0/" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">\
<responseDate>' + moment(Date.now(), "x").format("YYYY-MM-DDTHHmm:ssZ") + '</responseDate>\
<request verb="Identify">' + identifier + '</request>\
<Identify>\
<repositoryName>' + name + '</repositoryName>\
<baseURL>' + endpoint + '</baseURL>\
<protocolVersion>2.0</protocolVersion>\
<adminEmail>' + email + '</adminEmail>\
<earliestDatestamp>' + earliestDatestamp + '</earliestDatestamp>\
<deletedRecord>' + deletedRecord + '</deletedRecord>\
<granularity>' + granularity + '</granularity>\
</Identify>\
</OAI-PMH>'

API.oai.pmh.sets = (endpoint='https://api.lvatn.com/oai', sets=[{spec:Random.id(), name:'Example'}]) ->
  ret = '\
<OAI-PMH xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.openarchives.org/OAI/2.0/" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">\
<responseDate>' + moment(Date.now(), "x").format("YYYY-MM-DDTHHmm:ssZ") + '</responseDate>\
<request verb="ListSets">' + endpoint + '</request>\
<ListSets>'
  # what are set specs? doaj gen them as base64.urlsafe_b64encode(setspec).replace("=", "~")
  for set in sets # sets could be derived by a terms agg, ordered by term, with no counts, on a given key
    ret += '\
<set>\
<setSpec>' + set.spec + '</setSpec>\
<setName>' + set.name + '</setName>\
</set>'
  ret += '\
</ListSets>\
</OAI-PMH>'
  return ret
  
API.oai.pmh.formats = (endpoint='https://api.lvatn.com/oai', formats={'oai_dc': {schema: 'http://www.openarchives.org/OAI/2.0/oai_dc.xsd', namespace: 'http://www.openarchives.org/OAI/2.0/oai_dc/'}}) ->
  ret =  '\
<OAI-PMH xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.openarchives.org/OAI/2.0/" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">\
<responseDate>' + moment(Date.now(), "x").format("YYYY-MM-DDTHHmm:ssZ") + '</responseDate>\
<request verb="ListMetadataFormats">' + endpoint + '</request>\
<ListMetadataFormats>'
  for f of formats # could be configured in app settings, but more likely to be dependent on the service using this method (which may define them in its own app settings)
    ret += '\
<metadataFormat>\
<metadataPrefix>' + f + '</metadataPrefix>\
<schema>' + formats[f].schema + '</schema>\
<metadataNamespace>' + formats[f].namespace + '</metadataNamespace>\
</metadataFormat>'
  ret += '\
</ListMetadataFormats>\
</OAI-PMH>'
  return ret

API.oai.pmh.header = (rec) ->
  # what is identifier, do we need to know endpoint? and should it include collection type or not?
  # what is datestamp? Is it last updated value?
  res = '<header xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/">\
<identifier>oai:doaj.org/journal:546e6a5c78344571b07f160f37c6e01d</identifier>\
<datestamp>2018-07-23T11:20:30Z</datestamp>'
  for set in rec.sets
    # calculate the set spec from whatever is defined as sets - need to know which field in the record is being used as sets
    res += '<setSpec>TENDOkVkdWNhdGlvbg~~</setSpec>'
  res += '</header>'
  return res

API.oai.pmh.metadata = (rec) ->
  # need to know which metadata type is being used, and the necessary attributes to describe that
  res = '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/">'
  res += '<oai_dc:dc xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">'
  shortcode = 'dc'
  for field in ['title','identifier','relation','publisher','date']
    # but there can be more than one identifier, relation
    # also some of these fields may not be in fields with exactly the same name - identifier is probably a list of objects
    # so need to define the model that goes from one record format to the specified metadataPrefix output record format
    # and prob needs to be specific to the application, as will have different record types (perhaps more than one per app too)
    res += '<' + shortcode + ':' + field + '>' + rec[field] + '</' + shortcode + ':' + field + '>' if rec[field]?
    ### some examples:
    <dc:title>Journal of Information Technology Education: Innovations in Practice</dc:title>
    <dc:identifier>2165-3151</dc:identifier>
    <dc:relation>http://www.informingscience.us/icarus/journals/jiteiip/submitpaper</dc:relation>
    <dc:publisher>Informing Science Institute </dc:publisher>
    <dc:date>2012-06-13T14:40:20Z</dc:date>
    <dc:type>journal</dc:type>
    <dc:subject>information technology</dc:subject>
    <dc:subject xsi:type="dcterms:LCSH">Education</dc:subject>###
  res += '</oai_dc:dc>'
  res += '</metadata>'
  return res

API.oai.pmh.record = (endpoint='https://api.lvatn.com/oai', collection, identifier) ->
  # work out the ID from the identifier, and maybe the collection comes from there too
  rec = {}
  res = '' # what xml extra are needed for viewing just one record?
  res += API.oai.pmh.header rec
  res += API.oai.pmh.metadata rec # presumably record always contains metadata - does oai-pmh specify ability to request just a record header when not part of a list of records?
  # if cannot make this record into the request format, need to return CannotDisseminateFormat(base_url)
  return res

API.oai.pmh.records = (endpoint='https://api.lvatn.com/oai', collection, metadataPrefix='oai_dc', date_from, date_until, set, size=25, resumptionToken, metadata=true) ->
  # query the collection - may require some default filtering too, like in_doaj: true
  # d = { "range" : { "last_updated" : {"gte" : "<from date>", "lte" : "<until date>"} } }
  # if there is a from_date, set a bool must range query d["range"]["last_updated"]["gte"] = from_date
  # if until_date set d["range"]["last_updated"]["lte"] = until_date
  # if there is an oai_set filter {"term" : { "index.schema_subject.exact" : "<set name>" }}
  # set size if size is given, changing from default of 25 on doaj
  # create a resumption token that is the query that generated this result set, but change the from_date to be 1ms after the last_updated date of the last record in the result set being provided now
  # would these sequential individual filtered queries be better than keeping a scroll snapshot of the index open for a long time?
  # if there about 3 million records (size of doaj) and theu are served in batches of 25, 
  # if each query takes 5s (at the moment it is slow so actually takes even longer), it 
  # will take nearly a year and a half to get all the data in this way, so that is no good. 
  # using paging of 10000 it would take about 25 hours. That could be reasonable, but don't want 
  # many scroll snapshots for many different oai queries hanging around for a day at a time
  # do scroll snapshots share their "state"? Probably not
  #run the query and return the total and the hits
  #result = list_records(dao, request.base_url, specified, **params)
  if resumptionToken? and (not metadataPrefix? or not date_from? or not date_until? or not set?)
    return API.oai.pmh.bad 'argument', endpoint
  else if resumptionToken?
    try
      decoded = API.oai.pmh.resumptionToken.decode resumptionToken
      metadataPrefix = decoded.metadataPrefix if decoded.metadataPrefix?
      date_from = decoded.date_from
      date_until = decoded.date_until
      set = decoded.set
      size = decoded.size
    catch
      return API.oai.pmh.bad 'resumptionToken', endpoint

  formats = {} #get formats from config somehwere, or input to the method
  # only proceed with metadataPrefix, suitable format, suitable set, and dates that meet format and granularity reqs
  return API.oai.pmh.bad('argument',endpoint) if not metadataPrefix? # required by oai-pmh spec (although so far I set a default anyway)
  return API.oai.pmh.bad('format',endpoint) if not formats?[metadataPrefix]?
  return API.oai.pmh.bad('argument',endpoint) if ((date_from? and not API.oai.pmh.granularity(date_from)) or (date_until? and not API.oai.pmh.granularity(date_until)))
  try
    set = set #base64.urlsafe_b64decode(set.replace(/\~/g,"=")).decode("utf-8") if set? # change this from the python encode/decode to node
  catch
    return API.oai.pmh.bad 'argument', endpoint

  q = {} #build q using provided values
  recs = collection.search q
  if recs?.total? and recs.total isnt 0
    res = '<OAI-PMH xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.openarchives.org/OAI/2.0/" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">\
<responseDate>' + moment(Date.now(), "x").format("YYYY-MM-DDTHHmm:ssZ") + '</responseDate>\
<request verb="' + (if metadata then 'ListRecords' else 'ListIdentifiers') + '"'
    res += ' from="' + date_from + '"' if date_from? # note if using resumption tokens to adjust starting point, presumably this value still has to be the original query value - so track it through resumption tokens
    res += ' until="' + date_until + '"' if date_until?
    res += ' set="' + set + '"' if set?
    res += ' metadataPrefix="' + metadataPrefix + '"' if metadataPrefix?
    res += '>' + endpoint + '</request>'
    res += if metadata then '<ListRecords>' else '<ListIdentifiers>'
    for r in recs.hits.hits
      rec = recs.hits.hits[r]._source
      res += '<record>'
      res += API.oai.pmh.header rec
      res += API.oai.pmh.metadata(rec) if metadata
      res += '</record>'
    # example xml response below. Note that request attributes should be put in request element
    # put the results in the result object with correct format - each result needs header and metadata elements
    # can output more than one results metadata format at a time? or oai request only specifies just one?
    # add a resumption token if total is greater than results length - change the from date to the last_updated date of last record in current result set
    # if a resumption token was provided in this query but one is no longer needed, result should include the resumptionToken element but with no content
    # how long to honour resumption tokens? If setting a limit on them, need them to also contain their created timestamp - although that can be included as an option in the oai spec too
    # example <resumptionToken completeListSize="18" cursor="0" expirationDate="2018-07-24T13:14:21Z"/>
    res += if metadata then '</ListRecords>' else '</ListIdentifiers>'
    res += '</OAI-PMH>'
    return res
  else
    return API.oai.pmh.bad 'query', endpoint # would be the oai norecordsmatch response
  
API.oai.pmh.identifiers = (endpoint='https://api.lvatn.com/oai', collection, metadataPrefix='oai_dc', date_from, date_until, set, size=25, resumptionToken) ->
  # same as records, but only includes the headers, not the metadata
  return API.oai.pmh.records endpoint, collection, metadataPrefix, date_from, date_until, set, size, resumptionToken, false

API.oai.pmh.resumptionToken = (metadataPrefix, date_from, date_until, set) ->
  t = {}
  t.m = metadataPrefix if metadataPrefix?
  t.df = date_from if date_from?
  t.du = date_until if date_until?
  t.s = set if set?
  t.c = Date.now() # this actually needs to be expirationDate, so add any timeout length to now, and format how it is displayed, if displaying in the xml
  return '' #base64.urlsafe_b64encode JSON.stringify(t) #change to node version of base 64 encode
  # could just return the actual xml element here, xml should have attribute of completeListSize and cursor if paging, and also expirationDate if there is one set
  
API.oai.pmh.resumptionToken.decode = (resumptionToken) ->
  try
    token = JSON.parse(base64.urlsafe_b64decode(resumptionToken)) # change to node base 64
    t = {}
    # check token.c against any token expiry length settings, don't process it if too old, return false
    t.metadataPrefix = token.m if token.m?
    t.date_from = token.df if token.df?
    t.date_until = token.du if token.du?
    t.set = token.s if token.s
    return t
  catch
    return {}

API.oai.pmh.granularity = () ->
  # need a list of allowed granularity date formats
  # for any incoming date, try to format it to one of the allowed formats
  # if successful, the format is good. If not, it isn't throw an error
  return true
  
API.oai.pmh.bad = (err,endpoint) ->
  res = '\
<OAI-PMH xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.openarchives.org/OAI/2.0/" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
<responseDate>' + moment(Date.now(), "x").format("YYYY-MM-DDTHHmm:ssZ") + '</responseDate>
<request>' + endpoint + '</request>'
  if err is 'verb'
    res += '<error code="badVerb">Value of the verb argument is not a legal OAI-PMH verb, the verb argument is missing, or the verb argument is repeated.</error>'
  else if err is 'resumptionToken'
    res += '<error code="badResumptionToken">The value of the resumptionToken argument is invalid or expired.</error>'
  else if err is 'format'
    res += '<error code="cannotDisseminateFormat">The metadata format identified by the value given for the metadataPrefix argument is not supported by the item or by the repository.</error>'
  else if err is 'query'
    res += '<error code="noRecordsMatch">The combination of the values of the from, until, set and metadataPrefix arguments results in an empty list.</error>'
  else if err is 'noformat'
    res += '<error code="noMetadataFormats">There are no metadata formats available for the specified item.</error>'
  else if err is 'noID'
    res += '<error code="idDoesNotExist">The value of the identifier argument is unknown or illegal in this repository.</error>'
  else if err is 'nohierarchy'
    res += '<error code="noSetHierarchy">The repository does not support sets.</error>'
  else
    res += '<error code="badArgument">The request includes illegal arguments, is missing required arguments, includes a repeated argument, or values for arguments have an illegal syntax.</error>'
  res + '</OAI-PMH>'
  return res




'''
_illegal_unichrs = [(0x00, 0x08), (0x0B, 0x0C), (0x0E, 0x1F),
                    (0x7F, 0x84), (0x86, 0x9F),
                    (0xFDD0, 0xFDDF), (0xFFFE, 0xFFFF)]
if sys.maxunicode >= 0x10000:  # not narrow build
    _illegal_unichrs.extend([(0x1FFFE, 0x1FFFF), (0x2FFFE, 0x2FFFF),
                             (0x3FFFE, 0x3FFFF), (0x4FFFE, 0x4FFFF),
                             (0x5FFFE, 0x5FFFF), (0x6FFFE, 0x6FFFF),
                             (0x7FFFE, 0x7FFFF), (0x8FFFE, 0x8FFFF),
                             (0x9FFFE, 0x9FFFF), (0xAFFFE, 0xAFFFF),
                             (0xBFFFE, 0xBFFFF), (0xCFFFE, 0xCFFFF),
                             (0xDFFFE, 0xDFFFF), (0xEFFFE, 0xEFFFF),
                             (0xFFFFE, 0xFFFFF), (0x10FFFE, 0x10FFFF)])
_illegal_ranges = ["%s-%s" % (unichr(low), unichr(high))
                   for (low, high) in _illegal_unichrs]
_illegal_xml_chars_RE = re.compile(u'[%s]' % u''.join(_illegal_ranges))

def valid_XML_char_ordinal(i):
    return ( # conditions ordered by presumed frequency
        0x20 <= i <= 0xD7FF
        or i in (0x9, 0xA, 0xD)
        or 0xE000 <= i <= 0xFFFD
        or 0x10000 <= i <= 0x10FFFF
        )

def clean_unreadable(input_string):
    try:
        return _illegal_xml_chars_RE.sub("", input_string)
    except TypeError as e:
        app.logger.error("Unable to strip illegal XML chars from: {x}, {y}".format(x=input_string, y=type(input_string)))
        return None

def xml_clean(input_string):
    cleaned_string = ''.join(c for c in input_string if valid_XML_char_ordinal(ord(c)))
    return cleaned_string

def set_text(element, input_string):
    if input_string is None:
        return
    input_string = clean_unreadable(input_string)
    try:
        element.text = input_string
    except ValueError:
        element.text = xml_clean(input_string)
'''