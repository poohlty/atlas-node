# Node.js sever of @tlas server.
express = require('express')
http = require('http')
async = require('async')
request = require('request')
queryString = require('querystring')

# Define the app
app = express()

# Global service array. Keep record of all supported service.
services = ['panoramio', 'wikipedia']

# Turns a lat,lng,rad coord area into a rectangular area. Required by panoramio API
radiusToBounds = (lat, lng, radius) ->
  angle = radius / 6371000
  angle *= 57.2958
  lng_delta = Math.asin(Math.sin(angle / 57.2958) / Math.cos(lat / 57.2958)) * 57.2958
  result =
    radius: radius
    lat_orig: lat
    lng_orig: lng
    lat_min: lat - angle
    lat_max: lat + angle
    lng_min: lng - lng_delta
    lng_max: lng + lng_delta

# Build a query string based on coordinate and service.
buildQuery = (service, coord) ->
  switch service
    when 'wikipedia'
      queryObj =
        limit: 20
        lat: coord.lat_orig
        lng: coord.lng_orig
        radius: coord.radius
      root = "http://api.wikilocation.org/articles"
    when 'instagram'
      queryObj =
        lat: coord.lat_orig
        lng: coord.lng_orig
        distance: coord.radius
        access_token: "289166499.b87dcae.e7b77bc866f14d7084fb3018e16b38a3"
      root = "https://api.instagram.com/v1/media/search"
    when 'panoramio'
      queryObj =
        minx: coord.lng_min
        miny: coord.lat_min
        maxx: coord.lng_max
        maxy: coord.lat_max
        set: 'public'
        from: 0
        to: 20
        size: 'small'
        mapfilter: 'true'
      root = "http://www.panoramio.com/map/get_panoramas.php"
    when 'youtube'
      queryObj =
        v: 2
        alt: 'json'
        location: coord.lat_orig + ',' + coord.lng_orig
      queryObj['max-results'] = 25
      queryObj['location-radius'] = coord.radius + 'm'
      root = "https://gdata.youtube.com/feeds/api/videos"
    when 'twitter'
      queryObj =
        page: 1
        rpp: 100
        geocode: coord.lat_orig + "," + coord.lng_orig + "," + (coord.radius/1000) + 'km'
      root = "http://search.twitter.com/search.json"

  queryParam = queryString.stringify(queryObj)
  return root + '?' + queryParam

# Higher order function that return a function for mapping. The returned function calles and API and handles the response data.
createQuery = (coord) ->
  return (service, callback)->
    queryStr = buildQuery service, coord
    console.log queryStr

    request queryStr, (err, queryRes, body) ->
      if (!err && queryRes.statusCode is 200)
        result = JSON.parse body
        parsedResult = parseResponse service, result
        console.log parsedResult
        callback null, parsedResult

# Parse different response and create client readable data.
parseResponse = (service, response) ->
  result = []
  switch service
    when 'panoramio'
      for item in response['photos']
        obj =
          service: "panoramio"
          lat: item["latitude"]
          lng: item["longitude"]
          time: item["upload_date"] # Probably needs to parse it
          title: item["photo_title"]
          img_url: item["photo_file_url"]
          orig_url: item["photo_url"]
        result.push item
    when 'wikipedia'
      for item in response['articles']
        obj =
          service: "wikipedia"
          lat: item["lat"]
          lng: item["lng"]
          title: item["title"]
          img_url: "http://upload.wikimedia.org/wikipedia/commons/6/63/Wikipedia-logo.png"
          orig_url: item["url"]
        result.push item
  return result

# Handle get requests.
app.get "/", (req, res) ->
  # Only proceed with valid params.
  if req.query.lat? and req.query.lng? and req.query.radius
    lat = parseFloat req.query.lat
    lng = parseFloat req.query.lng
    radius = parseFloat req.query.radius
    coord = radiusToBounds lat, lng, radius

    # Build the API function used for mapping.
    APIquery = createQuery coord

    # Async mapping. Query all services asyncly.
    async.map services, APIquery, (err, result)->
      flattened = [].concat.apply([], result)
      console.log flattened
      console.log flattened.length
      res.send flattened

app.listen process.env.PORT or 8000
console.log "Server running at http://localhost:8000/"
