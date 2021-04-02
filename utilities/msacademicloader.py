
import json, requests, threading, os, re

batchsize = 10000 # how many records to batch upload at a time
loop = 1.0 # seconds loop between upload attempt
kind = 'journal'
target = 'http://localhost:3002/api/use/microsoft/graph/import?what=' + kind # where to send the records for upload

howmany = -1 # max number of lines to process. set to -1 to keep going
processsize = 200000 # how many lines to process per loop (so will generate up to this many files). set to -1 to keep going

infile = '/home/cloo/msacademic/mag_venues' # where the lines should be read from
outfolder = '/home/cloo/msacademic/records/' # where the generated files will go, and where they should be read and deleted from for uploading
lastfile = '/home/cloo/msacademic/last' # where to record the ID of the last item read from the file



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
        line = line.strip()
        js = json.loads(line)
        if waiting == True:
            if js['id'] == last:
                waiting = False
        else:
            prc += 1
            if js.get('DisplayName',False):
                js['title'] = js['DisplayName']
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
    print('processing done at ' + str(prc))
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