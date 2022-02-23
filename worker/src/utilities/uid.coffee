
import { customAlphabet } from 'nanoid'

P.uid = (length) ->
  length ?= if @fn is 'uid' then (this?.params?.len ? this?.params?.length ? this?.params?.size ? this?.params?.uid ? 21) else 21
  if typeof length is 'string'
    rs = parseInt length
    length = if isNaN(rs) then undefined else rs
  # have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  # are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  # will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  # without uppercases it's only a 1% chance if generating 1000 IDs per second for 131000 years.
  nanoid = customAlphabet (this?.params?.alphabet ? '0123456789abcdefghijklmnopqrstuvwxyz'), length
  return nanoid()
P.uid._cache = false

