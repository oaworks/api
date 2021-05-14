
import requests, json

batchsize = 50000 # how many records to batch upload at a time
target = 'http://localhost:3002/api/use/microsoft/graph/import?what=' # where to send the records for upload

kinds = ['abstract'] # ['journal', paper', 'author', 'affiliation', 'relation', 'abstract']
keys = {
    'journal': ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
    'author': ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
    'paper': ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate'],
    'affiliation': ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate'],
    'relation': ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation'],
    'abstract': ['PaperId', 'Abstract']
}

howmany = -1 # max number of lines to process. set to -1 to keep going

infolder = '~/mag/' # where the lines should be read from
lastfile = '~/mag/last' # prefix of where to record the ID of the last item read from the kind of file

def rebuild(idx):
    ind = json.load(idx)
    al = []
    while len(al) < ind['IndexLength']:
        al.append('')
    for k in ind['InvertedIndex']:
        for p in ind['InvertedIndex'][k]:
            al[p] = k
    return ' '.join(al)

def upload():
    total = 0
    
    for kind in kinds:
        print('MAG loader checking for ' + kind + ' files to load')
        kindtotal = 0

        tgt = target + kind
        kindlastfile = lastfile + '_' + kind
        infile = infolder + 'mag/' # note this would have to be nlp if the file is the abstracts file(s)
        if kind is 'journal':
            infile += 'Journals.txt'
        elif kind is 'paper':
            infile += 'Papers.txt'
        elif kind is 'author':
            infile += 'Authors.txt'
        elif kind is 'affiliation':
            infile += 'Affiliations.txt'
        elif kind is 'relation':
            infile += 'PaperAuthorAffiliations.txt'

        last = False
        waiting = False
        try:
            with open(kindlastfile, 'r') as ls:
                last = ls.readline()
                waiting = True
                print last
        except:
            pass

        batch = []
        try:
            fp = open(infile,'r')
            line = fp.readline()
            while line and (howmany is -1 or total < howmany):
                vals = line.split('\t')

                try:
                    if len(batch) >= batchsize:
                        print total
                        print kindtotal
                        r = requests.post(tgt, json=batch).json()
                        print(r.get('records',0))
                        if r.get('records',0) != len(batch):
                            print('Bulk records saved ' + str(r.get('records',0)) + ' does not match records sent ' + str(len(batch)) + ', aborting')
                            exit()
                        else:
                            batch = []
                            print vals[0]
                            with open(kindlastfile, 'w') as wl:
                                wl.write(vals[0])
                except:
                    print 'POST error... should continue'
                    pass

                if waiting == True:
                    if vals[0] == last:
                        waiting = False
                else:
                    total += 1
                    kindtotal += 1
                    kc = 0
                    if kind is 'relation':
                        obj = {}
                    else:
                        try:
                            obj = {'_id': vals[0].strip()}
                        except:
                            obj = {'_id': vals[0]}
                    if kind is 'abstract':
                        obj['PaperId'] = vals[0]
                        obj['Abstract'] = rebuild(vals[1])
                    else:
                        for key in keys[kind]:
                            try:
                                vs = vals[kc].strip()
                            except:
                                vs = vals[kc]
                            if vs != '':
                                obj[key] = vs
                            kc += 1
                    batch.append(obj)
                    
                line = fp.readline()
            fp.close()
        except Exception as e:
            print 'Error'
            print e

        if len(batch) != 0:
            r = requests.post(tgt, json=batch).json()
            print(r.get('records',0))
            
upload()