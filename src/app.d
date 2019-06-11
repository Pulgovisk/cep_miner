import std.stdio;
import std.net.curl;
import std.conv : to;
import std.utf : toUTF8;
import std.json;
import std.file : exists, chdir;
import html;
import core.thread;
import core.time;

string obter_nome_uf(string sUF) {
	switch (sUF) {
		case "AC":
			return "Acre";
		case "AL":
			return "Alagoas";
		case "AM":
			return "Amazonas";
		case "AP":
			return "Amapa";
		case "BA":
			return "Bahia";
		case "CE":
			return "Ceará";
		case "DF":
			return "Distrito Federal";
		case "ES":
			return "Espírito Santo";
		case "GO":
			return "Goiás";
		case "MA":
			return "Maranhão";
		case "MG":
			return "Minas Gerais";
		case "MS":
			return "Mato Grosso do Sul";
		case "MT":
			return "Mato Grosso";
		case "PA":
			return "Para";
		case "PB":
			return "Paraíba";
		case "PE":
			return "Pernambuco";
		case "PI":
			return "Piaui";
		case "PR":
			return "Parana";
		case "RJ":
			return "Rio de Janeiro";
		case "RN":
			return "Rio Grande do Norte";
		case "RO":
			return "Rondonia";
		case "RR":
			return "Roraima";
		case "RS":
			return "Rio Grande do Sul";
		case "SC":
			return "Santa Catarina";
		case "SE":
			return "Sergipe";
		case "SP":
			return "São Paulo";
		case "TO":
			return "Tocantins";

		default: assert(0, sUF);
	}
}

void salvar_json(JSONValue json) {
	{
		writeln("Gravando arquivo  ", api_base, "api\\v1\\cep\\", json["cep"].str);
		File file = File(api_base ~ "api\\v1\\cep\\" ~ json["cep"].str, "w"); 
		file.writeln(json.toPrettyString);
		file.close();
	}

	if ("ibge" in json) {
		writeln("Gravando arquivo  ", api_base, "api\\v1\\cod_ibge\\", json["ibge"].integer.to!string);
		File file = File(api_base ~ "api\\v1\\cod_ibge\\" ~ json["ibge"].integer.to!string, "w"); 
		file.writeln(json.toPrettyString);
		file.close();
	}
}

void update_git() {
	import std.process : executeShell;

	"Atualizando GIT...".writeln;

	immutable string git = "\"C:\\Program Files\\Git\\bin\\git.exe\"";
	executeShell(git ~ " add -A");
	executeShell(git ~ " commit -m \"Adicionado novos CEPs\"");
	executeShell(git ~ " push");
	executeShell(git ~ " gc");
}

enum api_base = "C:\\Temp\\cep_api\\";
enum ufs = [  "11", "12", "13", "14", "15", "16", "17", "21", "22", "23", "24", "25", "26", "27", "28", "29", "31", "32", "33", "35", "41", "42", "43", "50", "51", "52", "53" ];

void main(string[] args)
{
	chdir(api_base);

	foreach (uf; ufs) {
		string get_result = get("http://servicodados.ibge.gov.br/api/v1/localidades/estados/" ~ uf ~ "/municipios").to!string;

		JSONValue resultado = parseJSON(get_result);

		size_t consultado = 0;
		foreach (val; resultado.array) {
			writeln("Consultando para ", val["nome"].str, " ", val.object["microrregiao"].object["mesorregiao"].object["UF"]["sigla"].str);

			string result = post(
				"http://www.buscacep.correios.com.br/sistemas/buscacep/resultadoBuscaCepEndereco.cfm?t",
				[
					"relaxation": val["nome"].str ~ " " ~ val.object["microrregiao"].object["mesorregiao"].object["UF"]["sigla"].str,
					"tipoCEP": "LOG",
					"Metodo": "listaLogradouro",
					"TipoConsulta": "relaxation",
					"StartRow": "1",
					"EndRow": "1"
				]
			).to!string;

			consultado++;

			auto doc = createDocument!(DOMCreateOptions.None)(result);
			int current = 0;
			JSONValue json = JSONValue();

			foreach(p; doc.querySelectorAll(".tmptabela tr td")) {
				if (current == 0) {
					if (p.text.length > 6) {
						json["logradouro"] = p.text.toUTF8[0 .. $ - 6];
					}
					current++;
				} else if (current == 1) { 
					if (p.text.length > 6) {
						json["bairro"] = p.text.toUTF8[0 .. $ - 6];
					}
					current++;
				} else if (current == 2) { 
					import std.array : split;

					JSONValue cidade = JSONValue();
					auto splited = p.text.split("/");

					cidade["nome"] = splited[0].toUTF8;

					string sUF = splited[1].to!string()[0..2];
					cidade.object["estado"] = [ "sigla": sUF, "nome": obter_nome_uf(sUF) ];

					json["cidade"] = cidade;

					current++;
				} else if (current == 3) { 
					import std.array : replace;

					json["cep"] = p.text.replace("-", "");

					if (json.object["cidade"]["nome"].str == val["nome"].str &&
						json.object["cidade"].object["estado"]["sigla"].str == val.object["microrregiao"].object["mesorregiao"].object["UF"]["sigla"].str) {
						json["ibge"] = val["id"].integer;
					}

					salvar_json(json);

					current = 0;
					json = JSONValue();
				}
			}

			if (consultado % 25 == 0) {
				update_git();
			}
			Thread.sleep( dur!("seconds")( 5 ) );
		}
	}
}
