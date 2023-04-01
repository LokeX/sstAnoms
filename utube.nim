import asyncdispatch
import httpClient
import threadPool
import strutils
import sequtils
import browsers
import os

const 
  channelsFile = "channels.txt"
  startHTML = """
<!DOCTYPE html>
<html>
  <head>
		<meta charset="utf8">
		<meta name="viewport" content="width=device-width">
		<style type="text/css">
			body {
				background-color: #1B0C0C;
			}
			img {
				padding: 0px 10px 0px 0px;
			}
      a:link {
        text-decoration: none;
      }

      a:visited {
        text-decoration: none;
      }
      a:hover {
        color: darkgoldenrod;
        text-decoration: underline;
      }
      a:active {
        text-decoration: none;
      }			
      #textArea {
				padding: 1px 1px 1px 10px;
				width: 95%;
				border-style: inset;
				border: 3px groove;
				border-radius: 5px;
				border: 1px solid black;
				background-color: rgb(27, 27, 27);
				border-radius: 5px;
			}
			h1 {
				color: darkgoldenrod;
				font-family: Ariel;
				font-size: medium;
			}
			h2 {
				color: magenta;
				font-family: Ariel;
				font-size: large;
			}
		</style>
  </head>
  <body>
"""
  endHTML = """
  </body>
</html>
"""
  startRssHTML = """<div id="textArea">"""
  endRssHTML = """</div>"""

type RssEntry = tuple[header,name,time,url,nail:string]

func channelUrl(channel:string):string =
  "https://www.youtube.com/"&channel&"/videos"

func parseUrl(channelContent,urlId:string):string =
  let 
    pos = channelContent.find(urlId)
    urlStart = channelContent.find('"',pos+urlId.high+2)
    urlEnd = channelContent.find('"',urlStart+1)
  channelContent[urlStart+1..urlEnd-1]

func rssFieldsFilled(rssItem:RssEntry):bool =
  for field in rssItem.fields:
    if field.len == 0: return
  return true

func parseEntries(rss:string,maxEntries:int):seq[RssEntry] =
  let rssLines = rss.splitLines
  var newRssEntry:RssEntry
  result.add newRssEntry
  for line in rssLines[9..rssLines.high]:
    let ls = line.strip
    if ls.startsWith "<title>":
      result[^1].header = ls["<title>".len..ls.find("<",6)-1]
    elif ls.startsWith "<name>":
      result[^1].name = ls["<name>".len..ls.find("<",6)-1]
    elif ls.startsWith "<updated>":
      result[^1].time = ls["<updated>".len..ls.find("T",6)-1]
    elif ls.startsWith "<link":
      result[^1].url = ls[ls.find("http")..ls.find('>')-3]
    elif ls.startsWith "<media:thumbnail":
      result[^1].nail = ls[ls.find("http")..ls.find('"',25)-1]
    if result[^1].rssFieldsFilled:
      if result.len == maxEntries: return 
      result.add newRssEntry
  result.setLen result.len-1

proc urlFuture(url:string):Future[string] {.async.} =
  return await newAsyncHttpClient().getContent url

proc urlsGetContent(urls:openArray[string]):seq[string] =
  waitFor all urls.mapIt it.urlFuture

proc maxEntries:int =
  for param in commandLineParams():
    try: 
      result = param.parseInt 
      return
    except: discard
  return -1

func flatMap[T](x:seq[seq[T]]):seq[T] =
  for y in x:
    for z in y:
      result.add z

func generateHTML(rssEntries:openArray[RssEntry]):string =
  result.add startHTML
  for rssEntry in rssEntries:
    result.add startRssHTML
    result.add "<a href = \""&rssEntry.url&"\">"
    result.add "<img src = \""&rssEntry.nail&"\" width = \"100\" style = \"float:left;\">"
    result.add "<h2>"&rssEntry.name&": "&rssEntry.time&"</h2>"
    result.add "<h1>  "&rssEntry.header&"</h1>"
    result.add "</a>"
    result.add endRssHTML
    result.add "\n"
  result.add endHTML

proc gotParam(prm:string):bool =
  for param in commandLineParams():
    if param.toLower.startsWith prm: return true

proc channelsFileWith(prmChannel:string):seq[string] =
  if fileExists channelsFile:
    for line in lines channelsFile: result.add line
  if gotParam "-d": 
    result = result.filterIt(it != prmChannel) 
  elif prmChannel != "channelsFile" and result.find(prmChannel) == -1: 
    result.add prmChannel

proc paramChannel(default:string):string =
  for param in commandLineParams():
    if param.startsWith "@": 
      try: 
        discard newHttpClient().getContent channelUrl param
      except: return default
      return param.toLower
  default

proc allChannelsEntries(channels:openArray[string]):seq[RssEntry] =
  let max = maxEntries()
  channels.mapIt(it.channelUrl)
  .urlsGetContent
  .mapIt(spawn it.parseUrl "rssUrl")
  .mapIt(^it)
  .urlsGetContent
  .mapIt(spawn it.parseEntries(if max < 1: 1 else: max))
  .mapIt(^it)
  .flatMap

proc channelEntries(prmChannel:string):seq[RssEntry] =
  let
    http = newHttpClient()
    channelContent = http.getContent channelUrl prmChannel
    channelRssUrl = channelContent.parseUrl "rssUrl"
    rssLines = http.getContent(channelRssUrl)
  echo channelRssUrl  
  rssLines.parseEntries maxEntries()

proc write(channelEntries:seq[RssEntry])

let 
  prmChannel = paramChannel "channelsFile"
  channels = channelsFileWith prmChannel
  entries = 
    if gotParam("-d") or prmChannel == "channelsFile": 
      allChannelsEntries channels
    else: channelEntries prmChannel
if gotParam "-b": 
  writeFile "utube.html",generateHTML entries
  openDefaultBrowser "utube.html"
else: write entries
writeFile channelsFile,channels.join("\n")

import terminal
proc write(channelEntries:seq[RssEntry]) =
  for entry in channelEntries:
    stdout.styledWrite fgYellow,entry.name&": "
    stdout.styledWrite fgBlue,entry.time&": "
    stdout.styledWriteLine fgYellow,entry.header
    stdout.styledWriteLine fgMagenta,entry.url
