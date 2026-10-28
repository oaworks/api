
S.src.openai ?= {}
try S.src.openai = JSON.parse SECRETS_OPENAI

P.src.openai = {}


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
          }
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
