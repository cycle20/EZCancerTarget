//
// scancer.js:
//


const root_url = "https://version-11-5.string-db.org/";


//
// getSTRING: load STRING network image via dynamically added "img" tag
function getSTRING(id) {

    // GET parameters: key-value pairs
    var params = [
        [ 'species', '9606' ],
        [ 'identifiers', id ],
        [ 'required_score', '900' ],
        [ 'network_type', 'physical' ],
        [ 'network_flavor', 'evidence' ],
        [ 'block_structure_pics_in_bubbles', 1 ],
        [ 'caller_identity', 'https://github.com/cycle20/scancer/' ]
    ];
    // concatenate keys and values: separator: '='
    for (var index = 0; index < params.length; index++) {
        params[index] = params[index].join("=");
    }
    // concatenate key-value pairs: separator: '&'
    params = params.join("&");

    // get parent DOM element
    var stringDiv = document.getElementById(id);
    // Check for presence of 'img' element
    var imageCollection = stringDiv.getElementsByTagName("img");
    if (imageCollection.length === 0) {
        var anchor = document.createElement("a");
        anchor.text = `View network on ${root_url}`;
        stringDiv.appendChild(anchor);
        getNetworkLink(anchor, params);

        link = `${root_url}api/svg/network?${params}`;
        var STRING_img = document.createElement("img");
        STRING_img.src = link;
        STRING_img.alt = `STRING network image of ${id}`;
        stringDiv.appendChild(STRING_img);
    }
}


function getNetworkLink(anchor, paramString) {
  var request = new XMLHttpRequest();
  request.onreadystatechange = function() {
    if (this.readyState == 4 && this.status == 200) {
      var url = JSON.parse(this.responseText);
      if (url.length > 0) {
        anchor.href = url[0];
        anchor.target = "_blank";
      } else {
        anchor.text = "FAILED XHR request...";
      }
    }
  };
  var link = `${root_url}api/json/get_link?${paramString}`;
  request.open("GET", link, true);
  request.send();
}
