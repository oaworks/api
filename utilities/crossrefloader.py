
import json, requests, os, gzip, threading, re
from datetime import datetime

infolder = '/home/cloo/crossref/crossref/'
lastfile = '/home/cloo/crossref/last' # where to record the ID of the last file processed

target = 'http://localhost:3002/api/use/crossref/works/import' # where to send the records for upload

filenumber = 1 # crossref files are named by number, from 1, e.g. 1.json.gz
howmany = -1 # max number of records to process. set to -1 to keep going
batchsize = 12000 # how many records to batch upload at a time
loop = .3 # seconds loop between file read (files have 3k per file)

batch = [] # batch of json records to upload
done = 0



if os.path.exists(lastfile):
    with open(lastfile, 'r') as ls:
        filenumber = ls.readline()

filenumber = int(filenumber)
print('Starting at file number ' + str(filenumber))

def upload():
    global batch
    global batchsize
    global filenumber
    global done

    print('File number ' + str(filenumber) + ', done ' + str(done) + ', batch size ' + str(len(batch)))
    stopper = False

    tb = False

    f = gzip.open(infolder + str(filenumber) + '.json.gz', 'rb')
    content = f.read()
    f.close()
    print('File number ' + str(filenumber) + ' content length ' + str(len(content)))
    #if len(content) > 1000000000:
    #    tb = batchsize
    #    batchsize = 10
    recs = json.loads(content)
    lp = 0
    for rec in recs['items']:
        if not stopper:
            if howmany is -1 or done < howmany:
                done += 1
                rec['_id'] = rec.get('DOI').replace('/','_')
                rec['srcfile'] = filenumber
                rec['srcidx'] = lp
                lp += 1

                if rec.get('reference',False): # keep or just delete them all?
                    del rec['reference']
                    '''try:
                        refs = []
                        for ref in rec['reference']:
                            if ref.get('DOI',False):
                                rf = {'DOI': ref['DOI']}
                                if ref.get('article-title',False):
                                    rf.title = ref['article-title']
                                if ref.get('journal-title',False):
                                    rf.journal = ref.get('journal-title')
                                refs.append(rf)
                        rec['reference'] = refs
                    except:
                        del rec['reference']'''
                    
                if rec.get('relation',False):
                    del rec['relation']
                
                for p in ['published-print','published-online','issued','deposited','indexed']:
                    if rec.get(p,False):
                        try:
                            if 'T' in rec[p].get('date-time','') and len(rec[p]['date-time'].split('T')[0].split('-')) is 3:
                                if not rec.get('published',False): rec['published'] = rec[p]['date-time'].split('T')[0]
                                if not rec.get('year',False) and rec.get('published',False): rec['year'] = rec['published'].split('-')[0]
                        except:
                            pass
                        pbl = ''
                        try:
                            if len(rec[p].get('date-parts',[])) and len(rec[p]['date-parts'][0]) and rec[p]['date-parts'][0] and (not rec.get('published',False) or not rec[p].get('timestamp',False)):
                                rp = rec[p]['date-parts'][0] #crossref uses year month day in a list
                                pbl = str(rp[0])
                                if len(rp) is 1:
                                    pbl += '-01-01'
                                else:
                                    try:
                                        pbl += '-' + ('0' if len(str(rp[1])) is 1 else '') + str(rp[1])
                                    except:
                                        pbl += '-01'
                                    try:
                                        pbl += '-' + ('0' if len(str(rp[2])) is 1 else '') + str(rp[2])
                                    except:
                                        pbl += '-01'
                                if not rec.get('published',False):
                                    rec['published'] = pbl
                                    rec['year'] = pbl.split('-')[0]
                        except:
                            pass
                        try:
                            if not rec[p].get('timestamp',False) and len(pbl):
                                dt = datetime(int(pbl.split('-')[0]), int(pbl.split('-')[1]), int(pbl.split('-')[2]))
                                epoch = datetime.utcfromtimestamp(0)
                                rec[p]['timestamp'] = int((dt - epoch).total_seconds() * 1000)
                            if not rec.get('publishedAt',False) and rec[p].get('timestamp',False):
                                rec['publishedAt'] = rec[p]['timestamp']
                        except:
                            pass

                if rec.get('abstract',False): #and rec['abstract'].startswith('<'):
                    # keep abstract or just remove and add to separate index later?
                    del rec['abstract'] # only about 4.2m have abstracts so not much use until we get more from doiboost
                    #p = re.compile(r'<.*?>')
                    #rec['abstract'] = p.sub('', rec['abstract'])
                #if rec.get('abstract','').startswith('ABSTRACT'): rec['abstract'] = rec['abstract'].replace('ABSTRACT','')

                for a in rec.get('assertion',[]):
                    if a.get('label','False') is 'OPEN ACCESS':
                        if 'creativecommons' in a.get('URL',''):
                            if not rec.get('license',False): rec['license'] = []
                            rec['license'].append({'URL': a['URL']})
                        rec['is_oa'] = True

                for l in rec.get('license',[]):
                    if l.get('URL',False) and 'creativecommons' not in rec.get('licence','') and 'creativecommons' in l['URL']:
                        rec['licence'] = l['URL']
                        try:
                            rec['licence'] = 'cc-' + rec['licence'].split('/licenses/')[1].trim('/').replace('/','-')
                        except:
                            pass
                        rec['is_oa'] = True

                batch.append(rec)

            if len(batch) >= batchsize:
                r = requests.post(target,json=batch).json()
                print('POSTed batch of ' + str(len(batch)) + ' and ' + str(r.get('records',0)) + ' were confirmed')
                if r.get('records',0) != len(batch):
                    print('Bulk records saved ' + str(r.get('records',0)) + ' does not match records sent ' + str(len(batch)) + ', aborting')
                    stopper = True
                else:
                    with open(lastfile, 'w') as wl:
                        wl.write(str(filenumber))
                batch = []
        
    if not tb is False:
        batchsize = tb
    if not stopper:
        filenumber += 1
        if os.path.exists(infolder + str(filenumber) + '.json.gz') and (howmany is -1 or done < howmany):
            threading.Timer(loop, upload).start()
        else:
            if len(batch): # POST any stragglers
                r = requests.post(target,json=batch).json()
            print('Finished at file number ' + str(filenumber-1) + ', having done ' + str(done) + ' records')

upload()
