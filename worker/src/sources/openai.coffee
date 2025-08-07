
S.src.openai ?= {}
try S.src.openai = JSON.parse SECRETS_OPENAI

P.src.openai = {}

# https://platform.openai.com/docs/api-reference/chat/create
P.src.openai.chat = (prompt, role, model, json) ->
  prompt ?= @params.chat ? @params.prompt ? @params.q ? ''
  role ?= @params.role ? 'You are a helpful assistant'
  model ?= @params.model ? 'gpt-4-1106-preview'
  json ?= @params.json
  if typeof prompt is 'string' and prompt.length and @S.src.openai?.key
    url = 'https://api.openai.com/v1/chat/completions'
    headers = 'Content-Type': 'application/json', Authorization: 'Bearer ' + @S.src.openai.key
    msg = model: model, messages: []
    msg.response_format = {type: 'json_object'} if json
    system = role: 'system', content: role
    msg.messages.push system
    prompt = role: 'user', content: prompt
    msg.messages.push prompt
    res = await @fetch url, headers: headers, body: msg
    return res
  else
    res = {}

P.src.openai.chat._auth = '@oa.works'



P.src.openai.grantid = (prompt, text) ->
  prompt ?= @params.prompt ? 'Please extract the grant ID requested from the provided acknowledgements text.'
  text ?= @params.text ? 'Bill & Melinda Gates Foundation:\n\nThis work was supported by the USDA-NIFA Hatch/Multistate project W4147-TEN00539, the Bill and Melinda Gates Foundation (grant ID OPP1052983 and OPP1213329) and the Illumina Agricultural Greater Good Initiative grant.'
  if typeof text is 'string' and text.length and @S.src.openai?.key
    try
      url = 'https://api.openai.com/v1/chat/completions'
      headers = 'Content-Type': 'application/json', Authorization: 'Bearer ' + @S.src.openai.key

      msg = 
        model: "gpt-4o-2024-08-06",
        messages: [
          {
            "role": "system",
            "content": [
              {
                "text": prompt,
                "type": "text"
              }
            ]
          },
          {
            "role": "user",
            "content": [
              {
                "text": text,
                "type": "text"
              }
            ]
          }#, this is the example response
      #    {
      #      "role": "assistant",
      #      "refusal": false,
      #      "content": [
      #        {
      #          "text": "{\"grantid\":\"OPP1052983; OPP1213329\"}",
      #          "type": "text"
      #        }
      #      ]
      #    }
        ],
        response_format: {
          "type": "json_schema",
          "json_schema": {
            "name": "grantid_response",
            "schema": {
              "type": "object",
              "required": [],
              "properties": {
                "grantid": {
                  "type": [
                    "string",
                    "null"
                  ],
                  "description": "The grant id found, semi-colon seperated"
                }
              }
            },
            "strict": false
          }
        },
        temperature: 1,
        max_tokens: 256,
        top_p: 1,
        frequency_penalty: 0,
        presence_penalty: 0

      res = await @fetch url, headers: headers, body: msg
      return JSON.parse res.choices[0].message.content

  return {}

#P.src.openai.grantid._auth = '@oa.works'



P.src.openai.assistant = (assistant, message, thread, instruct, model) ->
  AI = new OpenAI apiKey: @S.src.openai.key
  assistant ?= @params.assistant #? 'asst_pYTJneAV4OE7x9YIKjG6yLaW'
  message ?= @params.message
  thread ?= @params.thread
  instruct ?= @params.instruct
  model ?= @params.model
  if assistant and message
    ret = assistant: assistant, thread: thread, message: message, response: undefined
    if thread
      ret.posted = await AI.beta.threads.messages.create thread, role: 'user', content: message
    else
      ret.posted = await AI.beta.threads.create messages: [role: 'user', content: message]
      ret.thread = ret.posted.id
    ret.run = await AI.beta.threads.runs.createAndPoll ret.thread, assistant_id: assistant, model: model, additional_instructions: instruct
    try ret.messages = await AI.beta.threads.messages.list ret.thread
    try ret.response = ret.messages.body.data[0].content[0].text.value
    try ret.response = JSON.parse ret.response
    delete ret.posted
    delete ret.run
    delete ret.messages
    return ret
P.src.openai.assistant._bg = true
#P.src.openai.assistant._auth = '@oa.works'
