/// Google Maps style tuned to the Kerb palette: warm paper surfaces, muted
/// petrol labels, POI/transit clutter off so tier-coloured pins carry the
/// information — same intent as the old Alidade Smooth basemap.
const kerbMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f6f4ef"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#43606c"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#f6f4ef"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative", "elementType": "geometry.stroke", "stylers": [{"color": "#e8e3d8"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry", "stylers": [{"color": "#f1eee6"}]},
  {"featureType": "poi", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"visibility": "on"}, {"color": "#e3ece2"}]},
  {"featureType": "poi.park", "elementType": "labels.text", "stylers": [{"visibility": "on"}, {"color": "#7c9a84"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#e8e3d8"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#77909b"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#f3e9d3"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#e6d9bd"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#cbdfdb"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#6d97a0"}]}
]
''';
