package cson;

import haxe.PosInfos;
import haxe.Json;
using StringTools;
using cson.CoolString;
typedef NodeVisitor = (Any, Dynamic) -> String;
typedef NodeOptions = {
    var ?bracesRequired:Bool;
}
// Comments don't have tokens because... C'mon :hueh:
enum Tokens {
	// Indent, in terms of cson, is equivilant to {
	Indent;
	// Dedent in terms of cson == }
	Dedent;
	Identifier(content:String);
	// ]
	RBrace;
	// [
	LBrace;
	NewLine;
	Colon;
	TString(content:String);
	TNumber(value:Float, int:Bool);
    TBool(value:Bool);
    TNull;
}

class Cson {
    public static function stringify(value:Dynamic, ?replacer:(key:Dynamic, value:Dynamic)->Dynamic, indent:Any):String {
        if (Reflect.isFunction(value))
            throw "Can't parse functions";

        var goodIndent = parseIndent(indent);

        final normalized = Json.parse(Json.stringify(value));

        return visitNode(normalized, null, goodIndent);
        
    }
    static final jsIdRE = ~/^[a-z_$][a-z0-9_$]*$/i;
    static final doubleQuotesRE = ~/''/g;
	static final SPACES = '          ';
    static function newlineWrap(str:Null<String>):String {
        return '\n${str}\n';
    }
    static function parseIndent(indent:Any):String {
        // unions aren't working, time for action
        if ((indent is Int)) {
            var oop:Int = cast indent;
            final n = Math.max(0, Math.min(10, Math.floor(oop)));
            return SPACES.substring(0, Std.int(n));
        } else if ((indent is String)) {
            var oop:String = indent;
            return oop.substring(0, 10);
        }
        return "";
    }
    static function indentLine(indent:String ,line:String):String {
        return indent + line;
    }
    static function indentLines(indent:String, str:String):String {
        if (str == '')
            return str;
        return str.split('\n').map(indentLine.bind(indent, _)).join('\n');
    }
    static function safeTrace<T>(thing:T):T {
        trace(thing);
        return thing;
    }
    static function singleQuoteStringify(str) {
		return "'" + Json.stringify(str).substring(1, Json.stringify(str).length - 1).replace('\\"', '"').replace("'", "\\'") + "'";
    }
    static function quoteType(str:String) {
        return str.contains("'") && !str.contains('"') ? 'double' : 'single';
    }
    static function onelineStringify(str:String) {
        return (quoteType(str) == 'single' ? singleQuoteStringify(str) : Json.stringify(str));
    }
    static function buildKeyPairs(indent:String, obj:Dynamic) {
        return Reflect.fields(obj).map((key) -> {
            final value = Reflect.field(obj, key);
            if (!jsIdRE.match(key)) {
                key = onelineStringify(key);
            }
            var serializedValue = visitNode(value, {
                bracesRequired: indent == ''
            }, indent);
            if (indent != '') {
                serializedValue = Type.typeof(value) == TObject && Reflect.fields(value).length >  0 ? '\n${indentLines(indent, serializedValue)}' : ' ${serializedValue}';
            }
            return '${key}:${serializedValue}';
        });
    }
    static function visitArray(indent:String, arr:Array<Dynamic>) {
        final items:Array<String> = arr.map(value -> {
            return visitNode(value, {
                'bracesRequired': true
            }, indent);
        });
        final serializedItems = indent != '' ? newlineWrap(indentLines(indent, items.join('\n'))) : items.join(',');
        return '[${serializedItems}]';
    }
    static function visitObject(indent:String, obj:Dynamic, arg:NodeOptions):String {
        final bracesReq = arg.bracesRequired;
        final keyPairs = buildKeyPairs(indent, obj);
        if (keyPairs.length == 0) return '{}';
        if (indent != '') {
            final keyPairsLines = keyPairs.join('\n');
            if (bracesReq) 
                return '{${newlineWrap(indentLines(indent, keyPairsLines))}}';
            return keyPairsLines;
        }

        final serializedPairs:String = keyPairs.join(',');
        if (bracesReq)
            return '{${serializedPairs}}';
        return serializedPairs;
    }
    static function visitString(indent:String, str:String):String {
        if (!str.contains('\n') || indent == '') {
            return onelineStringify(str);
        }
        final string = str.replace('\\', '\\\\').replace("''", "\\''");
        return "'''" + newlineWrap(indentLines(indent, string)) + indent + "'''";
    }
    static function visitNode(node:Dynamic, ?options:NodeOptions, indent:String):String {
        if (options == null) {
            options = {};
        }
		return switch Type.typeof(node) {
			case TNull: "null";
			case TInt: Std.string(node);
			case TFloat: Std.string(node);
			case TBool: (node : Bool) ? "true" : "false";
			case TObject:
				visitObject(indent, node, options);
			case TFunction: throw "NO FUNCTIONS";
			case TClass(c):
				if (c == String) visitString(indent, node) else if (c == Array) visitArray(indent, node) else throw "NO CLASSES";
			case TEnum(e): throw "NO ENUMS";
			case TUnknown: return '"???"';
            default: throw "oop-";
		}
    }
	// tokens : )
	public static function tokenize(str:String) {
		// only one indent token will be parsed on each line maximum. 
		// see: https://riptutorial.com/python/example/8674/how-indentation-is-parsed
		// tabs and spaces can be mixed but c'mon
		// :neutral_face:
		var lines = str.split('\n');
		// i only know how to parse stuff line by line : )
		var firstLine = true;
		var inMultilineComment = false;
        var inMultilineString = false;
        
		var tokens:Array<Tokens> = [];
        var validCharRegex = ~/[\w'"]/;
		var idRegex = ~/['"]?\w+['"]?/;
		var multicommentRegex = ~/#{3,6}.+?#{3,6}/g;
        var stringWithHash = ~/['"].*#.*['"]/g;
		var lineWithIgnoredComment = ~/(?:^.*#.*?)['"].*['"]/;
		// Amount of whitespace last line
		var arrayLevels = 0;
		var previousWS = 0;
		var thisWS = 0;
        var preferredWS = 0;
        var inArray = false;
        var technicallyInArray = false;
        var multiString = "";
		for (line in lines) {
            var justExitedMulti = false;
			thisWS = 0;
            // multiline strings ignore comments dumbass
            if (!inMultilineString) {
				if (line.contains('#') && !line.contains('###')) {
					// means this is a full line comment,
					// also means this doesn't become the first line, making object management easier
					if (line.ltrim().charAt(0) == '#') {
						continue;
						// it comments every thing after it
					} else {
                        if (line.count("'") > 0 || line.count('"') > 0) {
                            // oop
                            // we better check if it's in the string
                            // first lets make sure we aren't starting a multiline string which rules out all comments
                            if (~/'''/.match(line) && !~/#.*'''/.match(line)) {
                            // now if we match a line with a # in a string and it isn't commented out
                            } else if (stringWithHash.match(line) && !lineWithIgnoredComment.match(line)) {
                                // here we have to check the amount of them. 
                                if (line.count("#") > 1) {
                                    // We'll have to do some precision here. 
                                    var splitLine = line.split("");
                                    var pos = 0;
                                    var inString = false;
                                    var stringType = 'none';
                                    while (pos < splitLine.length) {
                                        var curChar = splitLine[pos++];
                                        switch (curChar) {
                                            case '\\':
                                                curChar = splitLine[pos++];
                                                switch (curChar) {
                                                    case '"' | "'":
                                                        if (inString)
                                                            continue;
                                                }
                                            case '"':
                                                if (stringType == 'double' || stringType == 'none') {
													inString = !inString;
													if (inString)
														stringType = 'double';
                                                    else 
                                                        stringType = 'none';
                                                }
                                                
                                            case "'":
												if (stringType == 'single' || stringType == 'none') {
													inString = !inString;
													if (inString)
														stringType = 'single';
													else
														stringType = 'none';
												}
                                            case "#": 
                                                if (!inString) {
                                                    // OOP
                                                    // rewind
                                                    pos--;
                                                    break;
                                                }
                                        }
                                    }
                                    if (pos < splitLine.length) {
                                        // We ingore the line after the hash. 
										line = line.substr(0, pos);
                                    }
                                }
                                // If that was false then we know it is a string like normal. 
							// Otherwise, it's probably fine, and we'll ignore it like normal.
                            } else {
								var pos = line.indexOf('#');
								line = line.substr(0, pos);
                            }
                        }
						
					}
				} else if (line.contains('###')) {
					// fuck
					
					if (multicommentRegex.match(line))
						line = multicommentRegex.map(line, (reg:EReg) -> return '');
					else {
						// fuck
						inMultilineComment = !inMultilineComment;
						// continue to make sure we don't include straight ###
						continue;
					}
				}
            }
			
			if (inMultilineComment) {
				// trace('ignoring stinky line ' + line);
				continue;
			}
            var isblankline = true;
            for (char in line.split("")) {
                if (!char.isSpace(0)) {
                    isblankline = false;
                    break;
                }
            }
			if (line.length == 0 || isblankline)
				continue;
            // We don't consume indents for arrays to preserve sanity.
			if (line.ltrim() != line && !inArray && line.trim() != "'''") {
				// if indented, consume indent
				// tokens.push(Indent);
                var safeLine = line;
				while (safeLine.isSpace(0)) {
					if (safeLine.charAt(0) == '\t') {
                        // fuck you a tab = space
						thisWS++;
					}
					if (safeLine.charAt(0) == ' ') {
						thisWS++;
					}
					safeLine = safeLine.substring(1);
				}
                line = safeLine;
                if (!inMultilineString) {
					if (thisWS > previousWS) {
						// only consume the indent if it is actually indented
						tokens.push(Indent);
					}
					if (thisWS < previousWS) {
						// This means we should have already initialized preferredWS.
						for (i in 0...Std.int((previousWS - thisWS) / preferredWS)) {
							// Push dedent tokens.
							tokens.push(Dedent);
						}
					}
					line = line.ltrim();
					if (preferredWS == 0) {
						// set preffered whitespace
						preferredWS = thisWS;
					} else if ((thisWS - previousWS) % preferredWS != 0) {
						// BAD >:(
						// This also discourages mixing tabs and spaces because who
						// the fuck knows what they mean

						throw "Mixed indentation";
					}
                }
                
			}
			// We know for a fact this line isn't a comment now. 
			// It could be blank tho :flushed:
			
			// lol nvm
			// time for action
            trace(inMultilineString);
            if (!inMultilineString) {
                // If we aren't in an array/multiline string, and this line isn't commented out/blank
                // That must mean we are about to parse an identifier/string and a value (which could be anything)
                // Some things MUST be parsed on the same line, i.e single line strings, numbers.
                // Other things might not, like arrays or objects. Arrays _usually_ start inline then can go for a while. 
                // First let's parse that dang identifier/string!
                var splitLine = line.split("");
                var field = "";
                var value:Dynamic = null;
                var arrayValue:Dynamic = null;
                var parsingIdentifier = !inArray;
                var pos = 0;
                var inlineMultiline = false;
                var stringType = 'none';
                var throwIfCharacterFound = false;
                while (pos < splitLine.length) {
                    var char = splitLine[pos++];
					switch (char) {
                        
						case _ if (parsingIdentifier && validCharRegex.match(char)):
							field += char;
						case ':' if (!inArray):
							parsingIdentifier = false;
                            if (field.contains('"') || field.contains("'")) {
                                field = field.substring(1, field.length -1);
                            }
                            
                            tokens.push(Identifier(field));
							field = "";
                            tokens.push(Colon);
                        case ':' if (inArray): 
                            // back the fuck up and parse the goddamn identifier
                            trace('oop');
                            var save = pos;
                            while (!validCharRegex.match(splitLine[pos--])) {
                                // do nothing
                            }
                            var end = pos;
                            while (validCharRegex.match(splitLine[pos--])) {
                                // do nothing
                            }
                            var id = line.substr(pos, end).ltrim();
                            pos = save;
                            // change to false. we are starting a :sparkles: new array
                            

                            inArray = false;
						    // also indents : )
                            previousWS = thisWS;
                            tokens.push(Identifier(id));
                            tokens.push(Colon);
                        case '\\' if (stringType != 'none'): 
                            char = splitLine[pos++];
                            switch (char) {
                                case '"':
                                    value += '"';
                                case '\\':
                                    value += '\\';
                                case "'": 
                                    value += "'";
                            }

                        case "'": 
                            // oop-
                            // let's look ahead. 
                            if (value == null) {
								value = "";
                                stringType = 'single';
                            }     
                            else {
                                // make sure we aren't being silly
                                if (stringType == 'double' || splitLine[pos - 1] == '\\' || stringType == 'none') {
									if (stringType != 'none')
										value += "'";
                                    continue; 
                                } 
                                // we aren't being silly :pog:
                                tokens.push(TString(value));
                            }
                                
                            var save = pos;
                            if (splitLine[pos++] == "'" && splitLine[pos++] == "'") {
                                if (inlineMultiline) {
                                    tokens.push(TString(value));
                                }
								var matchie = ~/'''/g;
                                if (matchie.match(line)) {
                                    try {
                                        matchie.matched(2);
                                    } catch (e:Any) {
										trace('starting multiline');
										multiString = line.split("'''")[1];
										inMultilineString = true;
                                        continue;
                                    }
                                    if (matchie.matched(2) != null ) {
                                        // thank christ
                                        // business as usual, except we ignore single quotes
                                        inlineMultiline = true;
                                        stringType = 'inline';
                                        continue;
                                    } else {
                                        // holy shit
                                        trace('starting multiline');
                                        multiString = line.split("'''")[1];
                                        inMultilineString = true;
                                        break;
                                    }
                                }
                             } else {
                                // just a regular string
                                pos = save;
                                // oop 
                                
                             }
                        case '"': 
							if (value == null) {
								value = "";
								stringType = 'double';
							} else {
								// make sure we aren't being silly
								if (stringType == 'single' || splitLine[pos - 1] == '\\' || stringType == 'none') {
                                    if (stringType != 'none')
                                        value += '"';
									continue;
								}
								// we aren't being silly :pog:
								tokens.push(TString(value));
							}
                        case _ if (stringType != 'none'): 
                            value += char; 
                        case _ if (stringType == 'none' && ~/[0-9\-]/.match(line)): 
                            var numString = char;
							while (splitLine[pos] != null && ~/[0-9.]/.match(splitLine[pos++])) {
                                numString += splitLine[pos - 1];
                            }
                            tokens.push(TNumber(Std.parseFloat(numString), !numString.contains(".")));
                        // we aren't parsing identifiers otherwise we wouldnt be here
                        case 't' if (stringType == 'none'): 
                             // look ahead
                             // we can throw if it isn't correct
                             var save = pos;
                             if (splitLine[pos++] != 'r' || splitLine[pos++] != 'u' || splitLine[pos++] != 'e') {
                                 throw 'Unexpected t, was expecting "true". line ${line} pos ${save}' ;
                             } 
                             tokens.push(TBool(true));
						case 'f' if (stringType == 'none'):
							// look ahead
							// we can throw if it isn't correct
							var save = pos;
							if (splitLine[pos++] != 'a' || splitLine[pos++] != 'l' || splitLine[pos++] != 's' || splitLine[pos++] != 'e') {
								throw 'Unexpected f, was expecting "false". line ${line} pos ${save}';
							}
							tokens.push(TBool(false));
						case 'n' if (stringType == 'none'):
							// look ahead
							// we can throw if it isn't correct
							var save = pos;
							if (splitLine[pos++] != 'u' || splitLine[pos++] != 'l' || splitLine[pos++] != 'l') {
								throw 'Unexpected n, was expecting "null". line ${line} pos ${save}';
							}
							tokens.push(TNull);
                        case ',':
                            // who put a comma here :angry:
                            // this means we have to parse it like...
                            // a regular json :scared:
                            // we do this because commas
                            if (arrayLevels > 0) {
                                // oh nevermind
								value = null;
                            } else {
								parsingIdentifier = true;
								field = "";
								value = null;
                            }
                            
                        case '[': 
                            // array :sweating:
                            arrayLevels++;
                            inArray = true;
                            tokens.push(LBrace);

                        case ']': 
                            arrayLevels--;
                            inArray = arrayLevels > 0;
                            tokens.push(RBrace);
                        case '\n' if (inArray):
                            tokens.push(NewLine);
                        
                        case ' ', '\t': 
                            // loop
						default:
                            // throw a goddamn hissy fit
                            // throw 'invalid char ${char}';
					}
                }
                // sanitycheck
                if (line.contains("'''")) {
                    continue;
                }
                
                
            }
            if (inMultilineString) {
                if (!line.contains("'''")) {
                    multiString += line + '\n';
                } else {
                    trace('ending');
                    multiString += line.split("'''")[0];
                    inMultilineString = false;
                    tokens.push(TString(multiString));
                    multiString = "";
                    justExitedMulti = true;
                }
            }
            firstLine = false;
            // Don't update indent when inArray
            // Or we might erroneously consume Indent/Dedent tokens
            // when it is over
            // same deal with multiline strings
            if (!inArray && !inMultilineString && !justExitedMulti)
			    previousWS = thisWS;
		}
        return tokens;
	}
    
}
