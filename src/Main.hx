package;
import haxe.Json;
import sys.io.File;
import cson.Cson;
class Main {
    public static function main() {
        var json = Json.parse(File.getContent('test.json'));

        File.saveContent('output.cson', Cson.stringify(json, null, 0));
    }
}