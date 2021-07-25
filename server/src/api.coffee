
import fetch from 'node-fetch' # used in fetch
import crypto from 'crypto' # used in utilities for hash generation
import http from 'http'
import https from 'https' # allows fetch to control https security for local connections
import Busboy from 'busboy'
import {promises as fs} from 'fs'
import tar from 'tar' # for tar file conversion
import zlib from 'zlib' # for reading/converting gz files


server = http.createServer (req, res) ->
  try
    ct = req.headers?['content-type'] ? req.headers?['Content-Type'] ? ''
    if ct.includes 'form'
      # example: curl -X POST 'https://example.com/convert?from=xls&to=csv' -F file=@anexcelfile.xlsx
      busboy = new Busboy headers: req.headers
      req.files = []
      waiting = true
      busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
        uf = {
          filename, 
          mimetype, 
          encoding, 
          fieldname, 
          data: null
        }
        buffers = []
        file.on 'data', (data) ->
          buffers.push data
        file.on 'end', () ->
          uf.data = Buffer.concat buffers
          req.files.push uf
      busboy.on 'field', (fieldname, value) -> 
        if fieldname.startsWith('{') and fieldname.endsWith('}')
          try jp = JSON.parse fieldname # someone prob sent json without encoding it properly
        if jp?
          req.body = jp
        else
          req.body ?= {}
          req.body[fieldname] = value
      busboy.on 'finish', () -> waiting = false
      req.pipe busboy
      while waiting
        await new Promise (resolve) => setTimeout resolve, 100
    else if req.method in ['POST', 'PUT']
      waiting = true
      haddata = false
      bd = ''
      req.on 'data', (d) -> 
        haddata = true
        bd += d
      req.on 'end', () -> waiting = false
      while waiting
        await new Promise (resolve) => setTimeout resolve, 100
      if haddata
        req.body = bd
  
  #try console.log(req.body) if S.dev and req.body?
  try
    try console.log('=== BG ' + req.method + ' ===', req.url) if S.dev
    pr = await P.call request: req
    try console.log('=== BG ' + req.method + ' DONE ===', pr.status) if S.dev
    try pr.headers['x-' + S.name.toLowerCase() + '-bg'] = true
    if req.url is '/'
      try
        pb = JSON.parse pr.body
        pb.bg = true
        pr.body = JSON.stringify pb, '', 2
        pr.headers['Content-Length'] = Buffer.byteLength pr.body
    res.writeHead pr.status, pr.headers # where would these be in a Response object from P?
    res.end pr.body
  catch err
    try console.log err
    headers = {}
    headers['x-' + S.name.toLowerCase() + '-bg'] = true
    res.writeHead 405, headers # where would these be in a Response object from P?
    res.end '405'

S.port ?= if S.dev then 4000 else 3000
server.listen S.port, 'localhost'

console.log S.name + ' v' + S.version + ' built ' + S.built + ', listening on ' + S.port

if S.demo
  console.log 'Congrats! You have a demo up and running'
  console.log 'NOTE: withhout any settings, this is only running locally for you, and should NOT be relied upon to store data'
  console.log 'Read more in the docs about settings and secrets, storing data in elasticsearch, and deployment options.'
  console.log 'You\'ll get this msg on each startup until you make some settings :)'
  console.log 'Thanks for trying Paradigm!' + (if S.docs then ' Learn more, and support us, at ' + S.docs else '')