import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Small original SVG line drawings, stored by stable names in the library.
// Each value is the inner markup of a 24x24 viewBox drawn stroke-only; the
// envelope (viewBox, stroke, caps, joins) lives in [AestheticIcon]. Names are
// persisted on saved records, so never rename or repaint an existing entry.
const aestheticIconPaths = <String, String>{
  // Light & weather.
  'sun':
      '<circle cx="12" cy="12" r="4"/><path d="M12 1v3m0 16v3M1 12h3m16 0h3M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
  'moon': '<path d="M20 15A9 9 0 0 1 9 3a9 9 0 1 0 11 12Z"/>',
  'star': '<path d="m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>',
  'cloud': '<path d="M6 19a5 5 0 0 1-1-10 7 7 0 0 1 13-1 6 6 0 0 1 0 11Z"/>',
  'rain':
      '<path d="M6.5 15a4.3 4.3 0 0 1-.5-8.4 6 6 0 0 1 11.2-1 4.8 4.8 0 0 1 .3 9.4Z"/><path d="M8 18v3m4-4v3m4-3v3"/>',
  'snowflake':
      '<path d="M12 2v20M3.3 7 20.7 17M20.7 7 3.3 17"/><path d="M9.9 6 12 4.8 14.1 6M9.9 18 12 19.2 14.1 18M16.2 7.2l2 1.2v2.4M18.2 13.2v2.4l-2 1.2M5.8 13.2v2.4l2 1.2M7.8 7.2l-2 1.2v2.4"/>',
  'fog':
      '<path d="M2 7q3-2 6 0t6 0 6 0M4 12q3-2 6 0t6 0M2 17q3-2 6 0t6 0 5 0"/>',
  'rainbow':
      '<path d="M3 20a9 9 0 0 1 18 0"/><path d="M6.5 20a5.5 5.5 0 0 1 11 0"/><path d="M10 20a2 2 0 0 1 4 0"/>',
  'sunrise':
      '<path d="M2 19h20M7 15a5 5 0 0 1 10 0"/><path d="M12 3v3M4.6 7.6l2.1 2.1M19.4 7.6l-2.1 2.1M2 15h2m18 0h-2"/>',
  'storm':
      '<path d="M7 13a4.2 4.2 0 0 1-1-7.9 7.5 7.5 0 0 1 11.4-1 4.6 4.6 0 0 1 .6 8.9Z"/><path d="m13.5 14-3.5 4.5h2.5l-1 3.5 3.5-4.5h-2.5Z"/>',
  'eclipse':
      '<circle cx="9.8" cy="12" r="5.6"/><circle cx="14.2" cy="12" r="5.6"/><path d="M12 1.8v2M12 20.2v2M1.8 12h2M20.2 12h2M4.9 4.9 6.3 6.3M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  'shooting-star':
      '<path d="m17 2.6 1.7 3.7 3.7 1.7-3.7 1.7-1.7 3.7-1.7-3.7-3.7-1.7 3.7-1.7Z"/><path d="M11 12.6 6.6 17M12.6 17.4l-3 3M6.6 11.4l-3 3"/>',

  // Nature.
  'mountain': '<path d="m2 21 8-17 5 10 3-6 5 13Zm5-10 3 2 3-2"/>',
  'leaf': '<path d="M3 21 18 6M4 17C-2 6 12 2 22 2c0 10-3 20-14 17"/>',
  'flower':
      '<circle cx="12" cy="12" r="3"/><path d="M9 9C1 2 12-2 12 7c0-9 11-5 3 2 8-7 12 4 3 3 9 0 5 11-3 3 8 8-3 12-3 3 0 9-11 5-3-3-8 8-12-3-3-3-9 1-5-10 3-3Z"/>',
  'waves':
      '<path d="M2 6q5-5 10 0t10 0M2 12q5-5 10 0t10 0M2 18q5-5 10 0t10 0"/>',
  'tree':
      '<path d="M12 2.5c2.5 0 4.5 1.8 4.9 4.2 2.3.4 4.1 2.4 4.1 4.8 0 2.7-2.2 4.9-4.9 4.9H7.9C5.2 16.4 3 14.2 3 11.5c0-2.4 1.8-4.4 4.1-4.8C7.5 4.3 9.5 2.5 12 2.5Z"/><path d="M10.4 16.4V21M13.6 16.4V21M8.4 21h7.2"/>',
  'pine':
      '<path d="m12 2 4 6H8Z"/><path d="m12 7 6 8H6Z"/><path d="M12 15v6M9.5 21h5"/>',
  'cactus':
      '<path d="M10 21V5a2 2 0 0 1 4 0v16"/><path d="M10 13H7.5A2.5 2.5 0 0 1 5 10.5V8"/><path d="M14 11h2.5A2.5 2.5 0 0 0 19 8.5V6"/><path d="M6.5 21h11"/>',
  'feather':
      '<path d="M6.5 18.6c-1-3.9.3-8.3 3.4-11.4 2.2-2.2 5-3.7 7.9-4.1 1 3.4.5 7-1.2 10-1.8 3.1-4.8 5.1-8.2 5.5Z"/><path d="M17.8 3.1 4 21"/><path d="m8.6 16.2 3.6-1.4M11 12.6l3.5-1.4M13.3 9.3l3.4-1.3"/>',
  'shell':
      '<path d="M12 20 3.5 10a9 9 0 0 1 17 0Z"/><path d="M12 20V4.2M12 20 6.5 6M12 20l5.5-14"/>',
  'mushroom':
      '<path d="M3 11a9 6 0 0 1 18 0Z"/><path d="M9.5 11v6a2.5 2.5 0 0 0 5 0v-6"/>',
  'wheat':
      '<path d="M12 22V6"/><path d="M12 6c-2 1.5-2 4 0 5.5 2-1.5 2-4 0-5.5Z"/><path d="M12 12.5c-2.4.6-4.2-1-4.4-3.3 2.4-.6 4.2 1 4.4 3.3Zm0 0c2.4.6 4.2-1 4.4-3.3-2.4-.6-4.2 1-4.4 3.3Z"/><path d="M12 18c-2.4.6-4.2-1-4.4-3.3 2.4-.6 4.2 1 4.4 3.3Zm0 0c2.4.6 4.2-1 4.4-3.3-2.4-.6-4.2 1-4.4 3.3Z"/>',
  'butterfly':
      '<path d="M12 6v11"/><path d="m12 6-2-2.5M12 6l2-2.5"/><path d="M12 8c-1.2-3.2-4.4-4.6-6.3-3.3-1.9 1.3-1.4 3.9.3 5.3-2 .5-3 3.3-1.2 4.9 1.8 1.6 5.4.3 7.2-2.9Z"/><path d="M12 8c1.2-3.2 4.4-4.6 6.3-3.3 1.9 1.3 1.4 3.9-.3 5.3 2 .5 3 3.3 1.2 4.9-1.8 1.6-5.4.3-7.2-2.9Z"/>',

  // Film & sound.
  'camera':
      '<rect x="2" y="6" width="20" height="15" rx="3"/><circle cx="12" cy="13" r="4"/><path d="m7 6 2-4h6l2 4"/>',
  'film':
      '<rect x="3" y="2" width="18" height="20" rx="2"/><path d="M7 2v20M17 2v20M3 7h4m-4 5h4m-4 5h4M17 7h4m-4 5h4m-4 5h4"/>',
  'clapperboard':
      '<rect x="2" y="3" width="20" height="18" rx="2"/><path d="M2 8h20"/><path d="m6 3-3 5m8-5-3 5m8-5-3 5m8-5-3 5"/>',
  'projector':
      '<rect x="2" y="10" width="15" height="9" rx="2"/><circle cx="6.5" cy="7" r="3"/><circle cx="13.5" cy="7" r="3"/><path d="m17 12.5 4.5-2v8l-4.5-2"/><path d="M5.5 19v2.5m8-2.5v2.5"/>',
  'film-reel':
      '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="6.2" r="2"/><circle cx="12" cy="17.8" r="2"/><circle cx="6.2" cy="12" r="2"/><circle cx="17.8" cy="12" r="2"/>',
  'lens':
      '<circle cx="12" cy="12" r="9.2"/><circle cx="12" cy="12" r="5"/><path d="M9 9.6A4 4 0 0 1 13.2 8.3"/><path d="M12 3v1.6m0 14.8V21M3 12h1.6m14.8 0H21"/>',
  'spotlight':
      '<path d="M9 2.5h6v5H9Z"/><path d="M8.7 8 4.8 17M15.3 8l3.9 9"/><ellipse cx="12" cy="20.2" rx="8.4" ry="2.2"/>',
  'retro-tv':
      '<rect x="2" y="7" width="20" height="13" rx="3"/><rect x="4.5" y="9.5" width="11" height="8" rx="2"/><circle cx="18.5" cy="11.5" r="1"/><circle cx="18.5" cy="15.5" r="1"/><path d="m8 7-3-4M14 7l3-4M5.5 20v2m13-2v2"/>',
  'microphone':
      '<rect x="9" y="2" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0"/><path d="M12 17.5V21M8.5 21h7"/>',
  'headphones':
      '<path d="M4 15v-3a8 8 0 0 1 16 0v3"/><rect x="2" y="14" width="4.5" height="7" rx="2.2"/><rect x="17.5" y="14" width="4.5" height="7" rx="2.2"/>',
  'vinyl':
      '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="3.5"/><circle cx="12" cy="12" r="1"/>',
  'radio':
      '<rect x="2" y="7.5" width="20" height="13" rx="2.5"/><circle cx="7.5" cy="14" r="3.5"/><path d="M13.5 11.5h6M13.5 14.5h6M13.5 17.5h3.5"/><path d="m16 7.5 4-4.5"/>',
  'cassette':
      '<rect x="2" y="5" width="20" height="14" rx="2"/><rect x="5" y="8.5" width="14" height="7" rx="1"/><circle cx="9" cy="12" r="1.6"/><circle cx="15" cy="12" r="1.6"/><path d="M7 19v-1.5m10 1.5v-1.5"/>',
  'music-note':
      '<path d="M9 18V4.5l10-2.5V16"/><ellipse cx="6" cy="18" rx="3" ry="2.4"/><ellipse cx="16" cy="16" rx="3" ry="2.4"/>',

  // Places.
  'skyline':
      '<path d="M2 21v-8h3v-4h4V4h4v9h3V8h4v13"/><path d="M2 21h20M11 4V2"/><path d="M11 7v1.5M11 10.5V12M3.5 16v1.5M18 11v1.5"/>',
  'house':
      '<path d="m2.5 10.5 9.5-7.5 9.5 7.5"/><path d="M5 8.6V21h14V8.6"/><path d="M9.5 21v-5.5h5V21"/>',
  'lighthouse':
      '<path d="M8 21 9.5 10h5L16 21Z"/><path d="M8.8 10V8h6.4v2"/><path d="M10 8V4.5h4V8"/><path d="M16.8 5.5 20.5 4M16.8 8 20.5 9.5M7.2 5.5 3.5 4M7.2 8 3.5 9.5"/><path d="M6 21h12"/>',
  'tent':
      '<path d="m12 4-9.5 16.5M12 4l9.5 16.5"/><path d="M2 20.5h20"/><path d="M12 9 8.5 20.5M12 9l3.5 11.5"/>',
  'bridge':
      '<path d="M4 18a8 8 0 0 1 16 0"/><path d="M2 18h20"/><path d="M12 10v8M7.5 11.4V18M16.5 11.4V18"/>',
  'road':
      '<path d="M3 21 9.5 3M21 21 14.5 3"/><path d="M12 20.5v-3.5M12 13.5v-3M12 7V4"/>',
  'castle':
      '<path d="M3 21V7h2v2.5h3V7h2.5v2.5h3V7h2.5v2.5h3V7h2v14Z"/><path d="M10 21v-4.5a2 2 0 0 1 4 0V21"/><rect x="5.8" y="12.5" width="2.4" height="3"/><rect x="15.8" y="12.5" width="2.4" height="3"/>',
  'pagoda':
      '<path d="M12 2.5V9"/><path d="M6 9q6-5 12 0M4 15q8-5 16 0M3 21q9-5 18 0"/><path d="M8.5 10v3.5M15.5 10v3.5M6.5 16v3.5M17.5 16v3.5M12 16v3.5"/>',
  'window':
      '<path d="M6 21V9a6 6 0 0 1 12 0v12Z"/><path d="M12 3.2V21M6 12.5h12"/><path d="M4.5 21h15"/>',

  // Objects.
  'diamond': '<path d="m2 8 5-6h10l5 6-10 14Zm0 0h20M7 2l5 20 5-20"/>',
  'eye':
      '<path d="M1 12Q12-3 23 12 12 27 1 12Z"/><circle cx="12" cy="12" r="3"/>',
  'palette':
      '<path d="M12 2a10 10 0 1 0 0 20c5 0-2-6 3-6 9 0 9-14-3-14Z"/><circle cx="7" cy="9" r="1"/><circle cx="12" cy="6" r="1"/><circle cx="17" cy="9" r="1"/>',
  'flame':
      '<path d="M13 2c2 8-7 7-5 13 3 0 5-4 5-6 10 9 4 14-2 13C0 21 3 11 7 8c0 5 2 5 2 5-2-5 3-7 4-11Z"/>',
  'sparkles': '<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3Z"/>',
  'bolt': '<path d="m14 1-12 13h9l-1 9L22 9h-9Z"/>',
  'key':
      '<circle cx="7.5" cy="8" r="4.5"/><circle cx="7.5" cy="8" r="1.5"/><path d="m10.7 11.2 9.3 9.3"/><path d="m14.6 15.1 1.8-1.8M17.2 17.7l1.8-1.8"/>',
  'compass':
      '<circle cx="12" cy="12" r="9.5"/><path d="m16.2 7.8-2.6 6.4-6.4 2.6 2.6-6.4Z"/>',
  'hourglass':
      '<path d="M6.5 2.5h11M6.5 21.5h11"/><path d="M8 2.5v4l4 5.5 4-5.5v-4M8 21.5v-4l4-5.5 4 5.5v4"/>',
  'umbrella':
      '<path d="M2.5 12a9.5 9.5 0 0 1 19 0q-2.4 2.5-4.75 0t-4.75 0-4.75 0-4.75 0Z"/><path d="M12 12v6.5a2.5 2.5 0 0 0 5 0"/>',
  'telescope':
      '<path d="m4.5 18 2-3.5 11-6.5 2 3.5Z"/><path d="m15.8 8.9 2 3.5"/><path d="M10.8 15.3 9 21M13.2 16.7 15 21M8 21h8"/>',
  'brush':
      '<path d="M20.6 3.4a2.2 2.2 0 0 0-3.1 0l-7.2 7.2 3.1 3.1 7.2-7.2a2.2 2.2 0 0 0 0-3.1Z"/><path d="m9.6 11 3.4 3.4"/><path d="M9.2 13.4c-2 .6-3.4 2.3-3.6 4.4-.1 1.4-.9 2.2-2.6 2.6 1.5 1.5 3.6 1.8 5.4.8 1.8-1 2.7-3 2.3-4.9Z"/>',
  'scissors':
      '<circle cx="6" cy="18.5" r="2.8"/><circle cx="18" cy="18.5" r="2.8"/><path d="M8 16.5 19 3M16 16.5 5 3"/>',

  // Voyage & science.
  'rocket':
      '<path d="M12 2c3 2.6 4.6 6.6 4.5 10.6L14.2 17H9.8L7.5 12.6C7.4 8.6 9 4.6 12 2Z"/><circle cx="12" cy="9.5" r="2"/><path d="M7.5 12.2 4.5 14.4V18l3.4-2.2M16.5 12.2l3 2.2V18l-3.4-2.2"/><path d="M10.2 18c.5 1.8 1.1 3.1 1.8 4 .7-.9 1.3-2.2 1.8-4"/>',
  'planet':
      '<circle cx="12" cy="12" r="5.5"/><path d="M21.1 7.8c.7 1.6-2.7 4.8-7.7 7.1-5 2.3-9.7 2.9-10.5 1.3-.7-1.6 2.7-4.8 7.7-7.1 5-2.3 9.7-2.9 10.5-1.3Z"/>',
  'globe':
      '<circle cx="12" cy="12" r="9.5"/><path d="M2.5 12h19"/><path d="M12 2.5c3 2.6 4.7 5.9 4.7 9.5s-1.7 6.9-4.7 9.5c-3-2.6-4.7-5.9-4.7-9.5s1.7-6.9 4.7-9.5Z"/>',
  'gear':
      '<path d="M9.7 2.9h4.6l-.5 2.8 2.8 1.6 2.2-1.8 2.2 3.9-2.6 1v3.2l2.6 1-2.2 3.9-2.2-1.8-2.8 1.6.5 2.8H9.7l.5-2.8-2.8-1.6-2.2 1.8L3 14.6l2.6-1v-3.2L3 9.4l2.2-3.9 2.2 1.8 2.8-1.6Z"/><circle cx="12" cy="12" r="3.4"/>',
  'clock': '<circle cx="12" cy="12" r="9.5"/><path d="M12 6.5V12l3.8 2.4"/>',
  'flask':
      '<path d="M9 2.5v6.5l-5.2 9A2.4 2.4 0 0 0 5.9 21.5h12.2a2.4 2.4 0 0 0 2.1-3.5L15 9V2.5"/><path d="M8 2.5h8M6.5 15.5h11"/>',
  'atom':
      '<circle cx="12" cy="12" r="1.8"/><path d="M21.3 12C21.3 14.1 17.1 15.8 12 15.8 6.9 15.8 2.7 14.1 2.7 12 2.7 9.9 6.9 8.2 12 8.2 17.1 8.2 21.3 9.9 21.3 12Z"/><path d="M16.7 20.1C14.8 21.1 11.3 18.3 8.7 13.9 6.1 9.5 5.5 5 7.3 3.9 9.2 2.9 12.7 5.7 15.3 10.1 17.9 14.5 18.5 19 16.7 20.1Z"/><path d="M7.4 20.1C5.5 19 6.1 14.5 8.7 10.1 11.3 5.7 14.8 2.9 16.6 3.9 18.5 5 17.9 9.5 15.3 13.9 12.7 18.3 9.2 21.1 7.4 20.1Z"/>',
  'anchor':
      '<circle cx="12" cy="4.5" r="2.5"/><path d="M12 7v14"/><path d="M8 10h8"/><path d="M5.5 12.5h-3a9.5 8.5 0 0 0 19 0h-3"/>',
  'paper-plane':
      '<path d="M21.5 2.5 2.5 10.8l7.6 3.1 3.1 7.6Z"/><path d="M21.5 2.5 10.1 13.9"/>',

  // Leisure.
  'heart':
      '<path d="M12 20.8S3 15.3 3 9.2A5.2 5.2 0 0 1 8.2 4c1.6 0 3 .7 3.8 1.9C12.8 4.7 14.2 4 15.8 4A5.2 5.2 0 0 1 21 9.2c0 6.1-9 11.6-9 11.6Z"/>',
  'book':
      '<path d="M12 6.5C10.5 5 8 4 5 4H2.5v13H5c3 0 5.5 1 7 2.5 1.5-1.5 4-2.5 7-2.5h2.5V4H19c-3 0-5.5 1-7 2.5Z"/><path d="M12 6.5v13"/>',
  'masks':
      '<path d="M2.5 4.5h9V12c0 3.3-2 5.8-4.5 5.8S2.5 15.3 2.5 12Z"/><path d="M5 8.2h1.2M7.8 8.2H9M5.2 12.8q1.8 1.8 3.6 0"/><path d="M12.5 6.5h9V14c0 3.3-2 5.8-4.5 5.8S12.5 17.3 12.5 14Z"/><path d="M15 10.2h1.2M17.8 10.2H19M15.2 15.4q1.8-1.8 3.6 0"/>',
  'crown':
      '<path d="M3.3 18.5 2.5 6.5l5.5 4L12 3.5l4 7 5.5-4-.8 12Z"/><path d="M3.7 14.5h16.6"/>',
  'martini': '<path d="M3 4.5h18l-9 8.5Z"/><path d="M12 13v6.5M7.5 20h9"/>',
  'coffee':
      '<path d="M3 8.5h13v6.5a5 5 0 0 1-5 5H8a5 5 0 0 1-5-5Z"/><path d="M16 10.5h2.5a2.75 2.75 0 0 1 0 5.5H16"/><path d="M6.5 6V3.5M10 6V3.5M13.5 6V3.5"/>',
  'bicycle':
      '<circle cx="6" cy="16.5" r="4"/><circle cx="18" cy="16.5" r="4"/><path d="M6 16.5 10 7.5h4.5l3.5 9"/><path d="M8.5 7.5h3M14 7.5h3"/><path d="M12 16.5 10 7.5"/>',
  'lamp':
      '<path d="M12 2v3.2"/><path d="M5 14 12 5.2 19 14Z"/><path d="M9.2 17.5h5.6M10.7 20.5h2.6"/>',

  // Shapes & marks.
  'circle': '<circle cx="12" cy="12" r="9.5"/>',
  'triangle': '<path d="M12 3 21.5 20H2.5Z"/>',
  'hexagon': '<path d="M12 2.5 20.2 7.2v9.6L12 21.5 3.8 16.8V7.2Z"/>',
  'spiral':
      '<path d="M12 12a1.5 1.5 0 0 1 1.5 1.5 3 3 0 0 1-3 3 4.5 4.5 0 0 1-4.5-4.5 6 6 0 0 1 6-6 7.5 7.5 0 0 1 7.5 7.5 9 9 0 0 1-7.5 7.5"/>',
  'infinity':
      '<path d="M12 12c-1.8-2.7-3.6-4-5.5-4a4 4 0 0 0 0 8c1.9 0 3.7-1.3 5.5-4Z"/><path d="M12 12c1.8 2.7 3.6 4 5.5 4a4 4 0 0 0 0-8c-1.9 0-3.7 1.3-5.5 4Z"/>',
  'asterisk': '<path d="M12 3v18M4.2 7.5l15.6 9M19.8 7.5l-15.6 9"/>',
  'target':
      '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1"/><path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22"/>',
  'grid':
      '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/>',
  'zigzag': '<path d="m2 17 4-10 4 10 4-10 4 10 4-10"/>',
  'starburst':
      '<path d="M12 2.4 13.1 7.7 16.8 3.7 15.1 8.9 20.3 7.2 16.3 10.9 21.6 12 16.3 13.1 20.3 16.8 15.1 15.1 16.8 20.3 13.1 16.3 12 21.6 10.9 16.3 7.2 20.3 8.9 15.1 3.7 16.8 7.7 13.1 2.4 12 7.7 10.9 3.7 7.2 8.9 8.9 7.2 3.7 10.9 7.7Z"/>',
};

/// Icon names grouped for the editor's picker, in display order. Every key
/// of [aestheticIconPaths] appears in exactly one group.
const aestheticIconGroups = <String, List<String>>{
  'Light & weather': <String>[
    'sun',
    'moon',
    'star',
    'cloud',
    'rain',
    'snowflake',
    'fog',
    'rainbow',
    'sunrise',
    'storm',
    'eclipse',
    'shooting-star',
  ],
  'Nature': <String>[
    'mountain',
    'leaf',
    'flower',
    'waves',
    'tree',
    'pine',
    'cactus',
    'feather',
    'shell',
    'mushroom',
    'wheat',
    'butterfly',
  ],
  'Film & sound': <String>[
    'camera',
    'film',
    'clapperboard',
    'projector',
    'film-reel',
    'lens',
    'spotlight',
    'retro-tv',
    'microphone',
    'headphones',
    'vinyl',
    'radio',
    'cassette',
    'music-note',
  ],
  'Places': <String>[
    'skyline',
    'house',
    'lighthouse',
    'tent',
    'bridge',
    'road',
    'castle',
    'pagoda',
    'window',
  ],
  'Objects': <String>[
    'diamond',
    'eye',
    'palette',
    'flame',
    'sparkles',
    'bolt',
    'key',
    'compass',
    'hourglass',
    'umbrella',
    'telescope',
    'brush',
    'scissors',
  ],
  'Voyage & science': <String>[
    'rocket',
    'planet',
    'globe',
    'gear',
    'clock',
    'flask',
    'atom',
    'anchor',
    'paper-plane',
  ],
  'Leisure': <String>[
    'heart',
    'book',
    'masks',
    'crown',
    'martini',
    'coffee',
    'bicycle',
    'lamp',
  ],
  'Shapes & marks': <String>[
    'circle',
    'triangle',
    'hexagon',
    'spiral',
    'infinity',
    'asterisk',
    'target',
    'grid',
    'zigzag',
    'starburst',
  ],
};

class AestheticIcon extends StatelessWidget {
  const AestheticIcon({
    super.key,
    required this.name,
    required this.color,
    this.size = 22,
  });
  final String name;
  final int color;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${aestheticIconPaths[name] ?? aestheticIconPaths['sparkles']}</svg>',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(Color(color), BlendMode.srcIn),
  );
}
