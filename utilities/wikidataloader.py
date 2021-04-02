
import json, requests, threading, os, re

batchsize = 10000 # how many records to batch upload at a time
loop = 2.0 # seconds loop between upload attempt
target = 'http://localhost:3002/api/use/wikidata/import' # where to send the records for upload

howmany = -1 # max number of lines to process. set to -1 to keep going
processsize = 200000 # how many lines to process per loop (so will generate up to this many files). set to -1 to keep going
infile = '/home/cloo/wikidata/latest-all.json' # where the lines should be read from
outfolder = '/home/cloo/wikidata/records/' # where the generated files will go, and where they should be read and deleted from for uploading
lastfile = '/home/cloo/wikidata/last' # where to record the ID of the last item read from the file
snaks = True
aliases = False
amounts = False
times = False
qualifiers = True
references = True
requiresitelinks = False
requireenlabel = True
requireendesc = False
mapproperties = False

properties = {}
try:
    r = requests.get('http://localhost:3002/api/use/wikidata/properties')
    properties = r.json()
    print(len(properties.keys()))
except:
    pass



def desnak(ms):
    snak = {}
    snak['property'] = ms['property'] # like PS30
    try:
        snak['key'] = properties[snak['property']]['label']
    except:
        pass
    if not ms.get('datavalue',{}).get('value',False):
        snak = False
    elif not isinstance(ms['datavalue']['value'],dict):
        snak['value'] = ms['datavalue']['value'] # an actual value
        if ms.get('datatype',False) == 'url': snak['url'] = snak['value']
    elif ms['datavalue']['value'].get('latitude',False):
        snak['location'] = {}
        snak['location']['latitude'] = ms['datavalue']['value']['latitude']
        snak['value'] = str(snak['location']['latitude'])
        if ms['datavalue']['value'].get('longitude',False):
            snak['location']['longitude'] = ms['datavalue']['value']['longitude']
            snak['value'] += ',' + str(snak['location']['longitude'])
        if ms['datavalue']['value'].get('precision',False): snak['precision'] = ms['datavalue']['value']['precision']
        if ms['datavalue']['value'].get('globe',False): snak['globe'] = ms['datavalue']['value']['globe'].split('/')[-1] # like Q2 is earth, could be dereferenced later
    elif ms['datavalue']['value'].get('amount',False):
        if amounts:
            snak['amount'] = ms['datavalue']['value']['amount']
            snak['value'] = snak['amount']
            if ms['datavalue']['value'].get('upperBound',False): snak['upperBound'] = ms['datavalue']['value']['upperBound']
            if ms['datavalue']['value'].get('lowerBound',False): snak['lowerBound'] = ms['datavalue']['value']['lowerBound']
            if ms['datavalue']['value'].get('unit',False): snak['unit'] = ms['datavalue']['value']['unit'].split('/')[-1] # like Q712226 is square kilometer, later deref
        else:
            snak = False
    elif ms['datavalue']['value'].get('time',False):
        if times:
            snak['time'] = ms['datavalue']['value']['time']
            snak['value'] = snak['time']
            if ms['datavalue']['value'].get('timezone',False): snak['timezone'] = ms['datavalue']['value']['timezone']
            if ms['datavalue']['value'].get('before',False): snak['before'] = ms['datavalue']['value']['before']
            if ms['datavalue']['value'].get('after',False): snak['after'] = ms['datavalue']['value']['after']
            if ms['datavalue']['value'].get('precision',False): snak['precision'] = ms['datavalue']['value']['precision']
        else:
            snak = False
    elif ms['datavalue']['value'].get('id',False):
        snak['qid'] = ms['datavalue']['value']['id'] # like Q32, so needs later dereference and value set in snak['value']
    if mapproperties and snak != False and snak.get('key',False) and snak.get('value',False):
        # there are ~7500 properties in wikidata so this will add up to 7500 values to the object mapping... is it worthwhile?
        # ES has a default of 1000 keys in a mapping, so no good by default anyway
        tk = re.sub(r'[^a-zA-Z0-9]', '', re.sub(r' ','_',snak['key']))
        snak[tk] = snak['value']
    if ms.get('qualifiers',False) and qualifiers and snak != False:
        snak['qualifiers'] = []
        for q in ms['qualifiers']:
            for qk in ms['qualifiers'][q]:
                snak['qualifiers'].append(desnak(qk))
    if ms.get('references',False) and references and snak != False:
        snak['references'] = []
        for r in ms['references']:
            for skid in r['snaks-order']:
                for ansk in r['snaks'][skid]:
                    snak['references'].append(desnak(ansk))
    return snak



fp = False
hm = 0
mk = 0
unsuitable = 0

def process():
    global fp
    global hm
    global mk
    global unsuitable
    
    print('processor processing lines from dump file')
    last = False
    waiting = False
    if fp == False:
        try:
            with open(lastfile, 'r') as ls:
                last = ls.readline()
        except:
            pass
        if last != False:
            waiting = True
        fp = open(infile,'r')

    line = fp.readline()
    prc = 0
    while line and (howmany is -1 or hm < howmany) and (processsize is -1 or prc < processsize):
        line = line.strip().strip(',')
        if line != '[' and line != ']':
            js = json.loads(line)
            if waiting == True:
                if js['id'] == last:
                    waiting = False
            else:
                prc += 1
                sl = {}
                for sw in js.get('sitelinks',[]):
                    if 'enwiki' in sw:
                        sl[sw] = js['sitelinks'][sw]
                label = js.get('labels',{}).get('en',{}).get('value',False)
                desc = js.get('descriptions',{}).get('en',{}).get('value',False)
                if requiresitelinks and len(sl.keys()) is 0:
                    #print('NO EN SITE LINKS ' + str(js['id']))
                    unsuitable += 1
                elif requireenlabel and label is False:
                    #print('NO EN LABEL ' + str(js['id']))
                    unsuitable += 1
                elif requireendesc and desc is False:
                    #print('NO EN DESC ' + str(js['id']))
                    unsuitable += 1
                else:
                    if js.get('aliases',False):
                        if aliases:
                            alias = []
                            for als in js['aliases']:
                                for al in js['aliases'][als]:
                                    alias.append(al)
                            js['alias'] = alias
                        del js['aliases']
                    if js.get('claims',False):
                        if snaks:
                            js['snaks'] = []
                            for s in js['claims']:
                                for sn in js['claims'][s]:
                                    ds = desnak(sn['mainsnak'])
                                    if ds: js['snaks'].append(ds)
                        del js['claims']
                    js['sitelinks'] = sl
                    del js['labels']
                    js['label'] = label
                    del js['descriptions']
                    js['description'] = desc
                    js['_id'] = js['id']
                    with open(outfolder+str(js['id'])+'.json', 'w') as out:
                        out.write(json.dumps(js, indent=2))
                with open(lastfile, 'w') as wl:
                    wl.write(js['id'])
                mk += 1
            hm += 1
            if (hm/float(1000)).is_integer():
                print(str(hm) + ' ' + str(mk) + ' ' + str(prc))
        line = fp.readline()
    print('processing done at ' + str(prc) + ' ' + str(unsuitable))
    if prc == 0:
        print('No more lines after made ' + str(mk))
        fp.close() # no more lines to process
    return prc



def upload():
    print('loader checking for files to load')
    fns = []
    counter = 0
    dump = []
    for filename in os.listdir(outfolder):
        if counter < batchsize:
            counter += 1
            fns.append(filename)
            with open(outfolder + '/' + filename) as fo:
                dump.append(json.load(fo))
        else:
            break
    print(counter)
    if len(dump) == 0:
        pr = process()
        if pr == 0:
            print('No more lines or files to process, or limit reached, done.')
        else:
            threading.Timer(loop, upload).start()
    else:
        r = requests.post(target,json=dump).json()
        print(r.get('records',0))
        if r.get('records',0) == len(dump):
            for fn in fns:
                os.remove(outfolder + '/' + fn)
            threading.Timer(loop, upload).start()
        else:
            print('bulk records saved ' + str(r.get('records',0)) + ' does not match records sent ' + str(len(dump)) + ', aborting')

upload()