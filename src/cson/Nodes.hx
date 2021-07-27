package cson;

class Nodes {
	public static final JS_KEYWORDS = [
		'true', 'false', 'null', 'this', 'new', 'delete', 'typeof', 'in', 'instanceof', 'return', 'throw', 'break', 'continue', 'debugger', 'yield', 'await',
		'if', 'else', 'switch', 'for', 'while', 'do', 'try', 'catch', 'finally', 'class', 'extends', 'super', 'import', 'export', 'default'
	];
	public static final COFFEE_KEYWORDS = [
		'undefined', 'Infinity', 'NaN', 'then', 'unless', 'until', 'loop', 'of', 'by', 'when'
	];
	public static final STRICT_PROSCRIBED = ['arguments', 'eval'];
	public static final RESERVED = [
		'case', 'function', 'var', 'void', 'with', 'const', 'let', 'enum', 'native', 'implements', 'interface', 'package', 'private', 'protected', 'public',
		'static'
	];
    public static function isUnassignable(name:String, ?displayName:String) {
        if (displayName == null)
            displayName = name;
        switch (name) {
            case _ if (COFFEE_KEYWORDS.contains(name) || JS_KEYWORDS.contains(name)):
                throw 'Key word ${displayName} can\'t be assigned.';
            case _ if (STRICT_PROSCRIBED.contains(name)):
                throw '${displayName} cannot be assigned.';
            case _ if (RESERVED.contains(name)):
                throw 'Reserved word ${displayName} cannot be assigned.';
            default:
                return true;
        }
    }
}

class Scope {
    // who the fuck knows, coffeescript has no type annotations
    public var parent:Scope;
    public var expressions:Dynamic;
    public function new(parent:Scope, expressions, method, refVars) {
        this.parent = parent;
        this.expressions = expressions;
    }
}