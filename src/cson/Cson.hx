package cson;

import haxe.PosInfos;
import haxe.Json;
using StringTools;
typedef NodeVisitor = (Any, Dynamic) -> String;
typedef NodeOptions = {
    var ?bracesRequired:Bool;
}
abstract Number(Float) from Float to Float {
    inline function new(i:Float) {
        this = i;
    }
    @:from
    static public function fromInt(s:Int) {
        return new Number(s);
    }
    @:to 
    public function toInt() {
        return Std.int(this);
    }
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
        return safeTrace(indent + line);
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
            return safeTrace('${key}:${serializedValue}');
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
        trace(keyPairs);
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
        trace(indent.length);
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
}
// This is based (lol) off the code of Haxe.json
class CsonParser {
	/**
		Parses given JSON-encoded `str` and returns the resulting object.
		JSON objects are parsed into anonymous structures and JSON arrays
		are parsed into `Array<Dynamic>`.
		If given `str` is not valid JSON, an exception will be thrown.
		If `str` is null, the result is unspecified.
	**/
	static public inline function parse(str:String):Dynamic {
		return new CsonParser(str).doParse();
	}

	var str:String;
	var pos:Int;
    var fileIndent:Int = 0;
	function new(str:String) {
		this.str = str;
		this.pos = 0;
	}

	function doParse():Dynamic {
		var result = parseRec();
		var c;
		while (!StringTools.isEof(c = nextChar())) {
			switch (c) {
				case ' '.code, '\r'.code, '\n'.code, '\t'.code:
				// allow trailing whitespace
				default:
					invalidChar();
			}
		}
		return result;
	}
    function parseObj():Dynamic {
        parsedAnythingYet = true;
		var obj = {}, field = null, comma:Null<Bool> = null;
		var quoteCount = 0;
		while (true) {
			var c = nextChar();
			if (c != "'".code)
				quoteCount = 0;

			switch (c) {
				case ' '.code, '\r'.code, '\n'.code, '\t'.code:
				// loop
				case '}'.code:
					if (field != null || comma == false)
						invalidChar();
					return obj;
				case ':'.code:
					if (field == null)
						invalidChar();
					Reflect.setField(obj, field, parseRec());
					field = null;
					comma = true;
				case ','.code:
					if (comma)
						comma = false
					else
						invalidChar();
				case '"'.code:
					if (field != null || comma)
						invalidChar();
					field = parseString();
				case "'".code:
					quoteCount++;
					if (quoteCount > 1) {
						invalidChar();
					}
				default:
					// invalidChar();
					// probably an indentifier?
					if (quoteCount != 0) {
						if (quoteCount == 1) {
							field = parseString(true);
							continue;
						}
					}
					field = parseIdentifier();
			}
		}
    }
    var parsedAnythingYet = false;
	function parseRec():Dynamic {
        var commentCount = 0;
        var allQuote = 0;
		while (true) {
			var c = nextChar();
            
			switch (c) {
				    
                    
				case '{'.code:
					return parseObj();
				case '['.code:
					var arr = [], comma:Null<Bool> = null;
					while (true) {
						var c = nextChar();
						switch (c) {
							case ' '.code, '\r'.code, '\t'.code:
							// loop
							case ']'.code:
                                // I doubt coffeescript is strict about commas
								//if (comma == false)
								//	invalidChar();
								return arr;
                            // newline is considered a seperator in cson
							case ','.code, '\n'.code:
								if (comma) comma = false else invalidChar();
							default:
								if (comma)
									invalidChar();
								pos--;
								arr.push(parseRec());
								comma = true;
						}
					}
				case 't'.code:
					var save = pos;
					if (nextChar() != 'r'.code || nextChar() != 'u'.code || nextChar() != 'e'.code) {
						pos = save;
						if (commentCount != 0) {
							handleComment(commentCount);
							continue;
						}
						if (allQuote == 0)
							invalidChar();
						else
							return handleQuote(allQuote);
					}
					parsedAnythingYet = true;
					return true;
				case 'f'.code:
					var save = pos;
					if (nextChar() != 'a'.code || nextChar() != 'l'.code || nextChar() != 's'.code || nextChar() != 'e'.code) {
						pos = save;
						if (commentCount != 0) {
							handleComment(commentCount);
							continue;
						}
						if (allQuote == 0)
							invalidChar();
						else
							return handleQuote(allQuote);
					}
					parsedAnythingYet = true;
					return false;
				case 'n'.code:
					var save = pos;
					if (nextChar() != 'u'.code || nextChar() != 'l'.code || nextChar() != 'l'.code) {
						pos = save;
                        if (commentCount != 0) {
							handleComment(commentCount);
                            continue;
                        }
                            
                        
                            
						if (allQuote == 0)
							invalidChar();
						else 
							return handleQuote(allQuote);
					}
					parsedAnythingYet = true;
					return null;
				case '"'.code:
					return parseString();
                case "'".code:
                    allQuote++;
				case '0'.code, '1'.code, '2'.code, '3'.code, '4'.code, '5'.code, '6'.code, '7'.code, '8'.code, '9'.code, '-'.code:
					return parseNumber(c);
                case '#'.code:
                    commentCount++;
                    if (commentCount == 3) {
                        handleComment(3);
                    }
				default:
					trace(allQuote);
                    if (allQuote != 0)
                        return handleQuote(allQuote);
                    if (commentCount != 0) {
                        handleComment(commentCount);
                        continue;
                    }
					if (c == ' '.code || c == '\r'.code || c =='\n'.code || c =='\t'.code) {
						continue;
					}
					
                    // if first character is some random ass character, it means we are dealing w/ an object
                    if (!parsedAnythingYet) {
                        parseObj();
						continue;
                    }
					invalidChar();
			}
			if (c != "'".code)
				allQuote = 0;
			if (c != "#".code)
				commentCount = 0;
			
		}
	}
    function handleQuote(count:Int):Dynamic {
        switch (count) {
            case 1:
                return parseString(true);
            case 3: 
                return parseString(false, true);
            default: 
                invalidChar();
        }
        return null;
    }
    function handleComment(count:Int) {
        if (count <= 0)
            invalidChar();
        if (count < 3) {
            ignoreLine();
        } else {
            var comments:Int = 0;
            while (true) {
                var c = nextChar();
                if (c == "#".code) {
                    comments++;
                } else {
                    comments = 0;
                }
                if (comments == 3) {
                    break;
                }
            }
        }

    }
	function parseString(?singlequote:Bool=false, ?multiline:Bool=false) {
		parsedAnythingYet = true;
		var start = pos;
		var buf:StringBuf = null;
		#if target.unicode
		var prev = -1;
		inline function cancelSurrogate() {
			// invalid high surrogate (not followed by low surrogate)
			buf.addChar(0xFFFD);
			prev = -1;
		}
		#end
        var multicount = 0;
		while (true) {
			var c = nextChar();
			if ((c == '"'.code && !singlequote && !multiline) || (c == "'".code && singlequote && !multiline))
				break;
            if (c == "'".code && multiline) 
                multicount++;
            else 
                multicount = 0;
            if (multiline && multicount >= 3) 
                break; 
			if (c == '\\'.code) {
				if (buf == null) {
					buf = new StringBuf();
				}
				buf.addSub(str, start, pos - start - 1);
				c = nextChar();
				#if target.unicode
				if (c != "u".code && prev != -1)
					cancelSurrogate();
				#end
				switch (c) {
					case "r".code:
						buf.addChar("\r".code);
					case "n".code:
						buf.addChar("\n".code);
					case "t".code:
						buf.addChar("\t".code);
					case "b".code:
						buf.addChar(8);
					case "f".code:
						buf.addChar(12);
					case "/".code, '\\'.code, '"'.code:
						buf.addChar(c);
					case 'u'.code:
						var uc:Int = Std.parseInt("0x" + str.substr(pos, 4));
						pos += 4;
						#if !target.unicode
						if (uc <= 0x7F)
							buf.addChar(uc);
						else if (uc <= 0x7FF) {
							buf.addChar(0xC0 | (uc >> 6));
							buf.addChar(0x80 | (uc & 63));
						} else if (uc <= 0xFFFF) {
							buf.addChar(0xE0 | (uc >> 12));
							buf.addChar(0x80 | ((uc >> 6) & 63));
							buf.addChar(0x80 | (uc & 63));
						} else {
							buf.addChar(0xF0 | (uc >> 18));
							buf.addChar(0x80 | ((uc >> 12) & 63));
							buf.addChar(0x80 | ((uc >> 6) & 63));
							buf.addChar(0x80 | (uc & 63));
						}
						#else
						if (prev != -1) {
							if (uc < 0xDC00 || uc > 0xDFFF)
								cancelSurrogate();
							else {
								buf.addChar(((prev - 0xD800) << 10) + (uc - 0xDC00) + 0x10000);
								prev = -1;
							}
						} else if (uc >= 0xD800 && uc <= 0xDBFF)
							prev = uc;
						else
							buf.addChar(uc);
						#end
					default:
						throw "Invalid escape sequence \\" + String.fromCharCode(c) + " at position " + (pos - 1);
				}
				start = pos;
			}
			#if !(target.unicode) // ensure utf8 chars are not cut
			else if (c >= 0x80) {
				pos++;
				if (c >= 0xFC)
					pos += 4;
				else if (c >= 0xF8)
					pos += 3;
				else if (c >= 0xF0)
					pos += 2;
				else if (c >= 0xE0)
					pos++;
			}
			#end
		    else if (StringTools.isEof(c))
			    throw "Unclosed string";
		}
		#if target.unicode
		if (prev != -1)
			cancelSurrogate();
		#end
		if (buf == null) {
			return str.substr(start, pos - start - 1);
		} else {
			buf.addSub(str, start, pos - start - 1);
			return buf.toString();
		}
	}
	function parseIdentifier() {
		parsedAnythingYet = true;
		var start = pos;
		var buf:StringBuf = null;
		#if target.unicode
		var prev = -1;
		inline function cancelSurrogate() {
			// invalid high surrogate (not followed by low surrogate)
			buf.addChar(0xFFFD);
			prev = -1;
		}
		#end
		while (true) {
			var c = nextChar();
			if (c == '"'.code || c == ':'.code)
				break;
            /*
			if (c == '\\'.code) {
				if (buf == null) {
					buf = new StringBuf();
				}
				buf.addSub(str, start, pos - start - 1);
				c = nextChar();
				#if target.unicode
				if (c != "u".code && prev != -1)
					cancelSurrogate();
				#end
				switch (c) {
					case "r".code:
						buf.addChar("\r".code);
					case "n".code:
						buf.addChar("\n".code);
					case "t".code:
						buf.addChar("\t".code);
					case "b".code:
						buf.addChar(8);
					case "f".code:
						buf.addChar(12);
					case "/".code, '\\'.code, '"'.code:
						buf.addChar(c);
					case 'u'.code:
						var uc:Int = Std.parseInt("0x" + str.substr(pos, 4));
						pos += 4;
						#if !target.unicode
						if (uc <= 0x7F)
							buf.addChar(uc);
						else if (uc <= 0x7FF) {
							buf.addChar(0xC0 | (uc >> 6));
							buf.addChar(0x80 | (uc & 63));
						} else if (uc <= 0xFFFF) {
							buf.addChar(0xE0 | (uc >> 12));
							buf.addChar(0x80 | ((uc >> 6) & 63));
							buf.addChar(0x80 | (uc & 63));
						} else {
							buf.addChar(0xF0 | (uc >> 18));
							buf.addChar(0x80 | ((uc >> 12) & 63));
							buf.addChar(0x80 | ((uc >> 6) & 63));
							buf.addChar(0x80 | (uc & 63));
						}
						#else
						if (prev != -1) {
							if (uc < 0xDC00 || uc > 0xDFFF)
								cancelSurrogate();
							else {
								buf.addChar(((prev - 0xD800) << 10) + (uc - 0xDC00) + 0x10000);
								prev = -1;
							}
						} else if (uc >= 0xD800 && uc <= 0xDBFF)
							prev = uc;
						else
							buf.addChar(uc);
						#end
					default:
						throw "Invalid escape sequence \\" + String.fromCharCode(c) + " at position " + (pos - 1);
				}
				start = pos;
			}
            
			#if !(target.unicode) // ensure utf8 chars are not cut
			else if (c >= 0x80) {
				pos++;
				if (c >= 0xFC)
					pos += 4;
				else if (c >= 0xF8)
					pos += 3;
				else if (c >= 0xF0)
					pos += 2;
				else if (c >= 0xE0)
					pos++;
			}
			#end
            */
		    else if (StringTools.isEof(c))
			    throw "Identifier has no value";
		}
		#if target.unicode
		if (prev != -1)
			cancelSurrogate();
		#end
		if (buf == null) {
			return str.substr(start, pos - start - 1);
		} else {
			buf.addSub(str, start, pos - start - 1);
			return buf.toString();
		}
	}
	inline function parseNumber(c:Int):Dynamic {
		parsedAnythingYet = true;
		var start = pos - 1;
		var minus = c == '-'.code, digit = !minus, zero = c == '0'.code;
		var point = false, e = false, pm = false, end = false;
		while (true) {
			c = nextChar();
			switch (c) {
				case '0'.code:
					if (zero && !point)
						invalidNumber(start);
					if (minus) {
						minus = false;
						zero = true;
					}
					digit = true;
				case '1'.code, '2'.code, '3'.code, '4'.code, '5'.code, '6'.code, '7'.code, '8'.code, '9'.code:
					if (zero && !point)
						invalidNumber(start);
					if (minus)
						minus = false;
					digit = true;
					zero = false;
				case '.'.code:
					if (minus || point || e)
						invalidNumber(start);
					digit = false;
					point = true;
				case 'e'.code, 'E'.code:
					if (minus || zero || e)
						invalidNumber(start);
					digit = false;
					e = true;
				case '+'.code, '-'.code:
					if (!e || pm)
						invalidNumber(start);
					digit = false;
					pm = true;
				default:
					if (!digit)
						invalidNumber(start);
					pos--;
					end = true;
			}
			if (end)
				break;
		}

		var f = Std.parseFloat(str.substr(start, pos - start));
		if (point) {
			return f;
		} else {
			var i = Std.int(f);
			return if (i == f) i else f;
		}
	}

	inline function nextChar() {
		return StringTools.fastCodeAt(str, pos++);
	}
    function ignoreLine() {
        while (nextChar() != '\n'.code) {
            
            trace('oop');
        }
		
    }
	function invalidChar() {
		pos--; // rewind
		throw "Invalid char " + StringTools.fastCodeAt(str, pos) + " at position " + pos;
	}

	function invalidNumber(start:Int) {
		throw "Invalid number at position " + start + ": " + str.substr(start, pos - start);
	}
}