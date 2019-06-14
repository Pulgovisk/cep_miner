import std.stdio;
import std.net.curl;
import std.conv : to;
import std.json;
import std.array : replace;
import std.file : exists, chdir;
import html;
import std.zlib;
import core.thread;
import core.time;


/// Retorno o nome completo da UF
string obter_nome_uf(string sUF)
{
	switch (sUF)
	{
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

	default:
		assert(0, sUF);
	}
}

///
void salvar_json(JSONValue json, string api_base)
{
	{
		writeln("Gravando arquivo  ", api_base, "api/v1/cep/", json["cep"].str);
		File file = File(api_base ~ "api/v1/cep/" ~ json["cep"].str, "w");
		file.writeln(json.toPrettyString);
		file.close();
	}

	if ("ibge" in json)
	{
		writeln("Gravando arquivo  ", api_base, "api/v1/cod_ibge/",
				json["ibge"].integer.to!string);
		File file = File(api_base ~ "api/v1/cod_ibge/" ~ json["ibge"].integer.to!string, "w");
		file.writeln(json.toPrettyString);
		file.close();
	}
}

///
void commit_to_git()
{
	import std.process : executeShell;

	"Atualizando o GIT...".writeln;

	version (Posix)
	{
		immutable string git = "git";
	}
	else
	{
		immutable string git = "\"C:\\Program Files\\Git\\bin\\git.exe\"";
	}

	executeShell(git ~ " add -A");
	executeShell(git ~ " commit -m \"Adicionado novos CEPs\"");
	//executeShell(git ~ " push");

	"GIT atualizado com sucesso".writeln;
}

///
static immutable ufs = [
	"34", "33", "32", "31", "29", "28", "27", "26", "25", "24", "23", "22",
	"21", "17", "16", "15", "14", "13", "12", "11"
];

void main(string[] args)
{
	if (args.length <= 1)
	{
		"Uso: cep_miner caminho_da_api".writeln;
		return;
	}

	chdir(args[1]);

	foreach (uf; ufs)
	{
		string get_result = get(
				"http://servicodados.ibge.gov.br/api/v1/localidades/estados/" ~ uf ~ "/municipios")
			.to!string;

	
		JSONValue resultado;
		try {
			resultado = parseJSON(get_result);
		}
		catch (JSONException) {
			ubyte[] deziped =  cast(ubyte[])new UnCompress(HeaderFormat.gzip).uncompress(get_result);
			resultado = parseJSON(cast(string)deziped);
		}
		size_t consultado = 0;
		foreach (val; resultado.array)
		{
			try
			{
				writeln("Consultando para ", val["nome"].str, "/",
						val.object["microrregiao"].object["mesorregiao"].object["UF"]["sigla"].str);

				auto http = HTTP();
				http.maxRedirects = uint.max;

				string result = post(
						"http://www.buscacep.correios.com.br/sistemas/buscacep/resultadoBuscaCepEndereco.cfm?t",
						["relaxation" : val["nome"].str ~ "/"
						~ val.object["microrregiao"].object["mesorregiao"].object["UF"]["sigla"].str, "Metodo"
						: "listaLogradouro", "TipoConsulta" : "relaxation",
						"StartRow" : "1", "EndRow" : "10"], http).to!string;

				consultado++;

				auto doc = createDocument!(DOMCreateOptions.None)(result);
				int current = 0;
				JSONValue json = JSONValue();

				foreach (p; doc.querySelectorAll(".tmptabela tr td"))
				{
					if (current == 0)
					{
						if (p.text.length > 6)
						{
							json["logradouro"] = p.text.replace("&nbsp", "");
						}
						current++;
					}
					else if (current == 1)
					{
						if (p.text.length > 6)
						{
							json["bairro"] = p.text.replace("&nbsp", "");
						}
						current++;
					}
					else if (current == 2)
					{
						import std.array : split;

						JSONValue cidade = JSONValue();
						auto splited = p.text.split("/");

						cidade["nome"] = splited[0].to!string;

						string sUF = splited[1].to!string()[0 .. 2];
						cidade.object["estado"] = ["sigla" : sUF, "nome" : obter_nome_uf(sUF)];

						json["cidade"] = cidade;

						current++;
					}
					else if (current == 3)
					{
						json["cep"] = p.text.replace("-", "");

						// dfmt off
					if (json.object["cidade"]["nome"].str == val["nome"].str && json.object["cidade"].object["estado"]["sigla"].str ==
							val.object["microrregiao"].object["mesorregiao"].object["UF"]["sigla"].str)
					{
						json["ibge"] = val["id"].integer;
					}
					// dfmt on

						salvar_json(json, args[1]);

						current = 0;
						json = JSONValue();
					}
				}

				version (Posix)
				{
					Thread.sleep(dur!"msecs"(1500));
				}

				if (consultado % 100 == 0)
				{
					commit_to_git();
				}

			}
			catch (CurlException e)
			{
				writeln("Erro no curl. Municipio ", val["nome"].str);
			}
			catch (JSONException e)
			{
				writeln("Erro no JSON. Municipio ", val["nome"].str);
			}
		}
	}
}
