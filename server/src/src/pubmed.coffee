
# https://www.nlm.nih.gov/databases/download/pubmed_medline.html
# https://www.nlm.nih.gov/bsd/licensee/2021_stats/2021_LO.html

# in case the medline data does not include all PMCs or PMIDs, there is a converter API
# and/or PMC sources that could be used to map things (with just over 6 million PMC IDs in the pubmed 
# data, looks like probably all PMC articles were in the data dump anyway)
# https://www.ncbi.nlm.nih.gov/pmc/tools/id-converter-api/
# https://www.ncbi.nlm.nih.gov/pmc/tools/ftp/

# annual files published each December, listed at: https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/
# lists files such as https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/pubmed21n0001.xml.gz
# up to 1062 for 2020. Contains other files including .md5 files for each gz file
# Managed to load 31847922
# PMID 30036026 failed with a “published” value of 1-01-01

# daily update files listed at https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/
# such as https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/pubmed21n1063.xml.gz
# can contain one or more files for each day since the last annual file dump

P.src.pubmed.load = (changes) ->
  # there are 30k or less records per pubmed file so tried batching by file, but streaming more than one file at a time caused OOM
  # so reduce batch size if necessary. default node heap size is 1400M I think, so increased to 3072M and try again
  # check if increasing heap that machine running it has enough - AND note that on production if using PM2 to run as cluster, then 
  # need enough memory for each process to max out. Running 3 with 15k batch size was stable but reaching almost 3000M at times and 
  # didn't seem much faster, so now set to do whole files as batches with two streamers at a time, see how that goes
  batchsize = -1 # how many records to batch upload at a time
  streamers = 2 # how many files to stream at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going...

  await @src.pubmed('') if @refresh and not changes

  addr = if changes then 'https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/' else 'https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/'
  files = []
  listing = await @fetch addr
  for a in listing.split 'href="'
    f = a.split('"')[0]
    if f.startsWith('pubmed') and f.endsWith('.gz') and ((@refresh and not changes) or not exists = await @src.pubmed.count undefined, 'srcfile:"' + addr + f + '"')
      files.push addr + f

  running = 0
  total = 0

  _loop = (fn) =>
    console.log 'Pubmed loading' + (if changes then ' changes' else ''), fn, files.length, running

    # stream them, unzip, and parse line by line, processing each record once a full record has been parsed out
    # the first 2020 gz file for example is 19M, uncompressed it is 182M. 30k records or so per file
    batch = []
    rec = {}
    published = false
    ininv = false
    for await line from readline.createInterface input: (await fetch fn).body.pipe zlib.createGunzip()
      if batchsize > 0 and batch.length >= batchsize
        await @src.pubmed batch
        batch = []
        console.log fn, total

      line = line.trim().replace('&amp;', '&')
      if line is '</PubmedArticle>' # <PubmedArticle>...</PubmedArticle> is a total article record
        total += 1
        if published isnt false and published.year
          rec.year = parseInt published.year
          if published.month and published.month.length > 2
            published.month = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf published.month.toLowerCase().substr(0, 3)
          published.month = published.month.toString() if typeof published.month is 'number'
          published.month = '0' + published.month if published.month and published.month.length is 1
          published.day = published.day.toString() if typeof published.day is 'number'
          published.day = '0' + published.day if published.day and published.day.length is 1
          rec.published = published.year + '-' + (published.month ? '01') + '-' + (published.day ? '01')
          rec.publishedAt = await @epoch rec.published
        rec.srcfile = fn
        rec._id = rec.PMID
        batch.push rec
        rec = {}
        published = false
        ininv = false
        break if total is howmany
      else
        km = 
          '<ArticleTitle>': 'title'
          '<AbstractText>': 'abstract'
          '<ISOAbbreviation>': 'iso'
          '<Issue>': 'issue' 
          '<Title>': 'journal'
          '<Language>': 'language'
          '<NlmUniqueID>': 'NLMID'
          '<PMID>': 'PMID'
          '<Volume>': 'volume'
          '<CopyrightInformation>': 'copyright'
          '<NumberOfReferences>': 'references_count'
          '<PublicationStatus>': 'status'
          '<SpaceFlightMission>': 'spaceflightmission'
        for k of km
          rec[km[k]] ?= line.split('>')[1].split('</')[0] if line.includes(k) or line.includes k.replace '>', ' '

        if line.includes '<MedlinePgn>'
          # do this because something like 1345-56 makes ES attempt to interpret a date, then others that don't look like a date will fail
          rec.pages = line.split('>')[1].split('</')[0].replace(' - ',' to ').replace('-', ' to ')
        
        if line.includes('<ISSN>') or line.includes('<ISSN ') or line.includes '<ISSNLinking>'
          rec.ISSN ?= []
          v = line.split('>')[1].split('</')[0]
          rec.ISSN.push(v) if v not in rec.ISSN
        if line.includes '<Keyword>'
          rec.keyword ?= []
          v = line.split('>')[1].split('</')[0]
          rec.keyword.push(v) if v not in rec.keyword
        if line.includes '<GeneSymbol>'
          rec.gene ?= []
          v = line.split('>')[1].split('</')[0]
          rec.gene.push(v) if v not in rec.gene
        if line.includes('<PublicationType>') or line.includes '<PublicationType '
          rec.type ?= []
          v = line.split('>')[1].split('</')[0]
          rec.type.push(v) if v not in rec.type

        if line.includes '<Chemical>'
          rec.chemical ?= []
          rec.chemical.push {}
        if line.includes('<NameOfSubstance>') or line.includes '<NameOfSubstance '
          rec.chemical[rec.chemical.length - 1].name = line.split('>')[1].split('</')[0]
          rec.chemical[rec.chemical.length - 1].nameID = line.split('UI="')[1].split('"')[0]
        if line.includes '<RegistryNumber>'
          rec.chemical[rec.chemical.length - 1].registry = line.split('>')[1].split('</')[0]

        if line.includes('<DataBank>') or line.includes '<DataBank '
          rec.databank ?= []
          rec.databank.push {}
        if line.includes '<DataBankName>'
          rec.databank[rec.databank.length - 1].name = line.split('>')[1].split('</')[0]
        if line.includes '<AccessionNumber>'
          rec.databank[rec.databank.length - 1].accession ?= []
          rec.databank[rec.databank.length - 1].accession.push line.split('>')[1].split('</')[0]

        if line.includes('<Grant>') or line.includes '<Grant '
          rec.grant ?= []
          rec.grant.push {}
        if line.includes '<GrantID>'
          rec.grant[rec.grant.length - 1].id = line.split('>')[1].split('</')[0]
        if line.includes '<Acronym>'
          rec.grant[rec.grant.length - 1].acronym = line.split('>')[1].split('</')[0]
        if line.includes '<Agency>'
          rec.grant[rec.grant.length - 1].agency = line.split('>')[1].split('</')[0]
        if line.includes '<Country>'
          if (not rec.grant or rec.grant[rec.grant.length - 1].country) and not rec.country
            rec.country = line.split('>')[1].split('</')[0]
          else
            rec.grant[rec.grant.length - 1].country = line.split('>')[1].split('</')[0]

        if line.includes('<MeshHeading>') or line.includes '<MeshHeading '
          rec.mesh ?= []
          rec.mesh.push {}
        if line.includes('<DescriptorName>') or line.includes('<DescriptorName ')
          rec.mesh[rec.mesh.length - 1].description = line.split('>')[1].split('</')[0]
          rec.mesh[rec.mesh.length - 1].descriptionID = line.split('UI="')[1].split('"')[0]
        if line.includes('<QualifierName>') or line.includes('<QualifierName ')
          rec.mesh[rec.mesh.length - 1].qualifier ?= []
          rec.mesh[rec.mesh.length - 1].qualifier.push name: line.split('>')[1].split('</')[0], id: line.split('UI="')[1].split('"')[0]

        if line.includes('<Investigator>') or line.includes '<Investigator '
          rec.author ?= []
          rec.author.push {}
          ininv = true
        if line.includes('<Author>') or line.includes '<Author '
          rec.author ?= []
          rec.author.push {}
          ininv = false
        try # some fields called PersonalNameSubjectList can cause a problem but don't know what they are so not including them
          if line.includes '<LastName>'
            rec.author[rec.author.length - 1].lastname = line.split('>')[1].split('</')[0]
            rec.author[rec.author.length - 1].investigator = true if ininv
          if line.includes '<ForeName>' # skip <Initials>
            rec.author[rec.author.length - 1].firstname = line.split('>')[1].split('</')[0]
          if line.includes '<Affiliation>'
            rec.author[rec.author.length - 1].affiliation = line.split('>')[1].split('</')[0]
          if line.includes '<Identifier>'
            rec.author[rec.author.length - 1].identifier = line.split('>')[1].split('</')[0]
            
        if line.includes('<Note>') or line.includes('<Note ') or line.includes('<GeneralNote>') or line.includes '<GeneralNote '
          try
            rec.notes ?= []
            rec.notes.push line.split('>')[1].split('</')[0]
            
        if line.includes('<DeleteCitation>') or line.includes '<DeleteCitation '
          rec.deletedFromMedline = true # this indicates Medline deleted the record, we should prob just remove all these too, but let's see how many there are

        if line.includes('<ArticleId>') or line.includes '<ArticleId '
          rec.identifier ?= {}
          idt = line.split('IdType="')[1].split('"')[0]
          rec.identifier[idt] ?= line.split('>')[1].split('</')[0]
          
        if line.includes('<ArticleDate>') or line.includes('ArticleDate ') or line.includes('<PubDate>') or line.includes '<PubDate '
          published = {}
        if published isnt false and (line.includes('<Year>') or line.includes('<Month>') or line.includes('<Day>'))
          published[line.split('>')[0].replace('<', '').toLowerCase()] = line.split('>')[1].split('</')[0]

    if batch.length
      await @src.pubmed batch
      batch = []
      console.log fn, total
    running -= 1

  while files.length
    break if howmany > 0 and total >= howmany
    await @sleep 1000
    if running < streamers
      running += 1
      _loop files.shift()

  console.log total
  #if not changes
  #  total += await @src.pubmed.changes true
  #  console.log total

  return total

P.src.pubmed.load._async = true
P.src.pubmed.load._auth = 'root'


P.src.pubmed.changes = () ->
  return @src.pubmed.load true

P.src.pubmed.changes._async = true
P.src.pubmed.changes._auth = 'root'


# https://www.nlm.nih.gov/bsd/serfile_addedinfo.html
# listing of all journals in pubmed, might be useful
#P.src.pubmed.journals.load = () ->


# https://www.nlm.nih.gov/bsd/licensee/elements_alphabetical.html
'''
<Abstract>
<AbstractText> found in <Abstract>; uses Label and NlmCategory attributes
<AccessionNumber> found in <DatabankList>
<AccessionNumberList> found in <DatabankList>
<Acronym> found in <GrantList>
<Affiliation> found in <AuthorList> and <InvestigatorList>
<AffiliationInfo> found in <AuthorList> and <InvestigatorList>; includes <Affiliation> and <Identifier>
<Agency> found in <GrantList>
<Article> uses PubModel attribute
<ArticleDate> uses DateType attribute
<ArticleId> found in <ArticleIdList>
<ArticleTitle>
<Author> found in <AuthorList>
<AuthorList> uses CompleteYN attribute
<Chemical> found in <ChemicalList>
<ChemicalList>
<CitationSubset>
CitedMedium attribute for <JournalIssue>
<CollectiveName> found in <Authorlist>
<CoiStatement>
<CommentsCorrections>
CompleteYN attribute for <AuthorList>, <DataBankList> and <GrantList>
<CopyrightInformation> found in <Abstract>, <OtherAbstract>
<Country>
<DataBank> found in <DataBankList>
<DataBankList> uses CompleteYN attribute
<DataBankName> found in <DataBankList>
<DateCompleted>
<DateCreated>
<DateRevised>
DateType attribute for <ArticleDate>
<Day> found in <ArticleDate>, <DateCompleted>, <DateCreated>, <DateRevised>,<PubDate>
<DeleteCitation>
<DescriptorName> found in <MeshHeadingList>; uses MajorTopicYN, Type and UI attributes
<ELocationID>
<ForeName> found in <AuthorList>, <InvestigatorList>, <PersonalNameSubjectList>
<GeneralNote> uses Owner attribute
<GeneSymbol> found in <GeneSymbolList>
<GeneSymbolList>
<Grant> found in <GrantList>
<GrantID> found in <GrantList>
<GrantList> uses CompleteYN attribute
<History>
<Identifier> found in <AuthorList> and <InvestigatorList>
<Initials> found in <AuthorList>, <InvestigatorList>, <PersonalNameSubjectList>
<Investigator> found in <InvestigatorList>
<InvestigatorList>
<ISOAbbreviation>
<ISSN> uses ISSNType attribute
<ISSNLinking>
ISSNType attribute for <ISSN>
<Issue>
<Journal>
<JournalIssue> uses CitedMedium attribute
<Keyword> found in <KeywordList>; uses MajorTopicYN attribute
<KeywordList> uses Owner attribute
Label attribute for <AbstractText>
<Language>
<LastName> found in <AuthorList>, <InvestigatorList>, <PersonalNameSubjectList>
MajorTopicYN attribute for <DescriptorName> and <QualiferName>
<MedlineCitation> uses Owner, Status, VersionID, and VersionDate attributes
<MedlineDate> found in <PubDate>
<MedlinePgn> found in <Pagination>
<MedlineTA>
<MeshHeading> found in <MeshHeadingList>
<MeshHeadingList>
<Month> found in <ArticleDate>, <DateCompleted>, <DateCreated>, <DateRevised>, <PubDate>
<NameOfSubstance> found in <ChemicalList>; uses UI attribute
NlmCategory attribute for <AbstractText>
<NlmUniqueID>
<Note> found in <CommentsCorrections>
<NumberOfReferences>
<OtherAbstract> uses Type and Language attributes
<OtherID> uses Source attribute
Owner attribute for <GeneralNote>, <KeywordList> and <MedlineCitation>
<Pagination>
<PersonalNameSubject> found in <PersonalNameSubjectList>
<PersonalNameSubjectList>
<PMID> also found in <CommentsCorrections>; uses Version attribute
PrintYN attribute for <JournalIssue>
<PubDate>
<PublicationStatus>
<PublicationType> found in <PublicationTypeList>; uses UI attribute
<PublicationTypeList>
<PubmedArticle>
<PubmedData>
<PubmedPubDate>
PubModel attribute for <Article>
<QualifierName> found in <MeshHeadingList>; uses MajorTopicYN and UI attributes
<RefSource> found in <CommentsCorrections>
<RefType> attribute for <CommentsCorrections>
<RegistryNumber> found in <ChemicalList>
<SpaceFlightMission>
Source attribute for <OtherID>
Status attribute for <MedineCitation>
<Suffix> found in <AuthorList>, <InvestigatorList>, <PersonalNameSubjectList>
<SupplMeshList>
<SupplMeshName> found in <SupplMeshList>; uses Type and UI attributes
<Title>
Type attribute for <Descriptor Name>, <OtherAbstract>, and <SupplMeshName>
<VernacularTitle>
VersionDate attribute for <MedlineCitation>
VersionID attribute for <MedlineCitation>
<Volume>
<Year> found in <ArticleDate>, <DateCompleted>, <DateCreated>, <DateRevised>,<PubDate>
'''

'''
<PubmedArticle>
  <MedlineCitation Status="MEDLINE" Owner="NLM">
    <PMID Version="1">1</PMID>
    <DateCompleted>
      <Year>1976</Year>
      <Month>01</Month>
      <Day>16</Day>
    </DateCompleted>
    <DateRevised>
      <Year>2019</Year>  
      <Month>02</Month>
      <Day>08</Day>
    </DateRevised>
    <Article PubModel="Print">
      <Journal>
        <ISSN IssnType="Print">0006-2944</ISSN>          
        <JournalIssue CitedMedium="Print">            
          <Volume>13</Volume>            
          <Issue>2</Issue>            
          <PubDate>              
            <Year>1975</Year>              
            <Month>Jun</Month>            
          </PubDate>          
        </JournalIssue>          
        <Title>Biochemical medicine</Title>          
        <ISOAbbreviation>Biochem Med</ISOAbbreviation>        
      </Journal>        
      <ArticleTitle>Formate assay in body fluids: application in methanol poisoning.</ArticleTitle>        
      <Pagination>          
        <MedlinePgn>117-26</MedlinePgn>        
      </Pagination>        
      <AuthorList CompleteYN="Y">          
        <Author ValidYN="Y">            
          <LastName>Makar</LastName>            
          <ForeName>A B</ForeName>            
          <Initials>AB</Initials>          
        </Author>          
        <Author ValidYN="Y">            
          <LastName>McMartin</LastName>            
          <ForeName>K E</ForeName>            
          <Initials>KE</Initials>          
        </Author>          
        <Author ValidYN="Y">            
          <LastName>Palese</LastName>            
          <ForeName>M</ForeName>            
          <Initials>M</Initials>          
        </Author>          
        <Author ValidYN="Y">            
          <LastName>Tephly</LastName>            
          <ForeName>T R</ForeName>            
          <Initials>TR</Initials>          
        </Author>        
      </AuthorList>        
      <Language>eng</Language>        
      <GrantList CompleteYN="Y">          
        <Grant>            
          <GrantID>MC_UU_12013/5</GrantID>            
          <Agency>MRC</Agency>            
          <Country>United Kingdom</Country>          
        </Grant>        
      </GrantList>  
      <PublicationTypeList>          
        <PublicationType UI="D016428">Journal Article</PublicationType>          
        <PublicationType UI="D013487">Research Support, U.S. Gov't, P.H.S.</PublicationType>        
      </PublicationTypeList>      
    </Article>      
    <MedlineJournalInfo>        
      <Country>United States</Country>        
      <MedlineTA>Biochem Med</MedlineTA>        
      <NlmUniqueID>0151424</NlmUniqueID>        
      <ISSNLinking>0006-2944</ISSNLinking>      
    </MedlineJournalInfo>      
    <ChemicalList>        
      <Chemical>          
        <RegistryNumber>0</RegistryNumber>          
        <NameOfSubstance UI="D005561">Formates</NameOfSubstance>   
      </Chemical>        
      <Chemical>          
        <RegistryNumber>142M471B3J</RegistryNumber>          
        <NameOfSubstance UI="D002245">Carbon Dioxide</NameOfSubstance>        
      </Chemical>        
      <Chemical>        
        <RegistryNumber>EC 1.2.-</RegistryNumber>          
        <NameOfSubstance UI="D000445">Aldehyde Oxidoreductases</NameOfSubstance>        
      </Chemical>        
      <Chemical>          
        <RegistryNumber>Y4S76JWI15</RegistryNumber>          
        <NameOfSubstance UI="D000432">Methanol</NameOfSubstance>        
      </Chemical>      
    </ChemicalList>      
    <CitationSubset>IM</CitationSubset>      
    <MeshHeadingList>        
      <MeshHeading>  
        <DescriptorName UI="D000445" MajorTopicYN="N">Aldehyde Oxidoreductases</DescriptorName>          
        <QualifierName UI="Q000378" MajorTopicYN="N">metabolism</QualifierName>        
      </MeshHeading>      
      <MeshHeading>          
        <DescriptorName UI="D000818" MajorTopicYN="N">Animals</DescriptorName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D001826" MajorTopicYN="N">Body Fluids</DescriptorName>          
        <QualifierName UI="Q000032" MajorTopicYN="Y">analysis</QualifierName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D002245" MajorTopicYN="N">Carbon Dioxide</DescriptorName>          
        <QualifierName UI="Q000097" MajorTopicYN="N">blood</QualifierName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D005561" MajorTopicYN="N">Formates</DescriptorName>          
        <QualifierName UI="Q000097" MajorTopicYN="N">blood</QualifierName>          
        <QualifierName UI="Q000506" MajorTopicYN="Y">poisoning</QualifierName>        
      </MeshHeading>       
      <MeshHeading>          
        <DescriptorName UI="D000882" MajorTopicYN="N">Haplorhini</DescriptorName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D006801" MajorTopicYN="N">Humans</DescriptorName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D006863" MajorTopicYN="N">Hydrogen-Ion Concentration</DescriptorName>        
      </MeshHeading>        
      <MeshHeading>    
        <DescriptorName UI="D007700" MajorTopicYN="N">Kinetics</DescriptorName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D000432" MajorTopicYN="N">Methanol</DescriptorName>   
        <QualifierName UI="Q000097" MajorTopicYN="N">blood</QualifierName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D008722" MajorTopicYN="N">Methods</DescriptorName>        
      </MeshHeading>        
      <MeshHeading>          
        <DescriptorName UI="D011549" MajorTopicYN="N">Pseudomonas</DescriptorName>          
        <QualifierName UI="Q000201" MajorTopicYN="N">enzymology</QualifierName>    
      </MeshHeading>      
    </MeshHeadingList>    
  </MedlineCitation>    
  <PubmedData>      
    <History>        
      <PubMedPubDate PubStatus="pubmed">          
        <Year>1975</Year>          
        <Month>6</Month>          
        <Day>1</Day>        
      </PubMedPubDate>        
      <PubMedPubDate PubStatus="medline">          
        <Year>1975</Year>          
        <Month>6</Month>          
        <Day>1</Day>          
        <Hour>0</Hour>          
        <Minute>1</Minute>  
      </PubMedPubDate>        
      <PubMedPubDate PubStatus="entrez">          
        <Year>1975</Year>          
        <Month>6</Month>          
        <Day>1</Day>          
        <Hour>0</Hour>          
        <Minute>0</Minute>        
      </PubMedPubDate>      
    </History>      
    <PublicationStatus>ppublish</PublicationStatus>      
    <ArticleIdList>        
      <ArticleId IdType="pubmed">1</ArticleId>        
      <ArticleId IdType="doi">10.1016/0006-2944(75)90147-7</ArticleId>      
    </ArticleIdList>    
  </PubmedData>  
</PubmedArticle>
'''

