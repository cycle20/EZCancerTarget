//
// scancer.js:
//


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

    root_url = "https://version-11-0b.string-db.org/";
    // get parent DOM element
    var stringDiv = document.getElementById(id);
    // Check for presence of 'img' element
    var imageCollection = stringDiv.getElementsByTagName("img");
    if (imageCollection.length == 0) {
        var STRING_img = document.createElement("img");
        STRING_img.src = `${root_url}api/svg/network?${params}`;
        STRING_img.alt = `STRING network image of ${id}`;
        stringDiv.appendChild(STRING_img);
    }
}
