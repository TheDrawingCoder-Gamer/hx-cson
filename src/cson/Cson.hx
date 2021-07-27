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