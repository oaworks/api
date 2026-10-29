
S.src.doaj ?= {}
try S.src.doaj.secrets = JSON.parse SECRETS_DOAJ

P.src.doaj = {}

P.src.doaj.journals = _index: true, _prefix: false

P.src.doaj.journals.load = () ->
  fldr = '/tmp/doaj_' + await @uid()
  await fs.mkdir fldr
  fldr += '/'
  await fs.writeFile fldr + 'doaj.tar', await @fetch 'https://doaj.org/public-data-dump/journal?api_key=' + S.src.doaj.secrets.apikey, buffer: true
  tar.extract file: fldr + 'doaj.tar', cwd: fldr, sync: true # extracted doaj dump folders end 2020-10-01
  current = false
  for f in await fs.readdir fldr
    current = f if f.includes 'doaj_journal_data'
  total = 0
  if current
    journals = JSON.parse await fs.readFile fldr + current + '/journal_batch_1.json'
    total = journals.length
    await @src.doaj.journals ''
    await @src.doaj.journals journals
    await fs.unlink fldr + current + '/journal_batch_1.json'
  await fs.rmdir fldr + current
  await fs.unlink fldr + 'doaj.tar'
  await fs.rmdir fldr
  return total
P.src.doaj.journals.load._bg = true
P.src.doaj.journals.load._async = true
P.src.doaj.journals.load._auth = '@oa.works'

