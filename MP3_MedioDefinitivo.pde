import controlP5.*;
import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.effects.*;
import ddf.minim.ugens.*;
import java.util.*;
import java.net.InetAddress;
import javax.swing.*;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;
import org.elasticsearch.action.admin.indices.exists.indices.IndicesExistsResponse;
import org.elasticsearch.action.admin.cluster.health.ClusterHealthResponse;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.action.index.IndexResponse;
import org.elasticsearch.action.search.SearchResponse;
import org.elasticsearch.action.search.SearchType;
import org.elasticsearch.client.Client;
import org.elasticsearch.common.settings.Settings;
import org.elasticsearch.node.Node;
import org.elasticsearch.node.NodeBuilder;
// Constantes para referir al nombre del indice y el tipo
static String INDEX_NAME = "canciones";
static String DOC_TYPE = "cancion";

FFT fftLin;
float spectrumScale = 4;

ControlP5 cp5;
ScrollableList list;

Client client;
Node node;



ControlP5 play, pause, Volup, Voldown, fSel, HPass, LPass;
Minim minim;
AudioPlayer song;
FilePlayer cancion;
boolean playing=false, h=false, l=false;
String path;
float volume=0;
AudioMetaData meta;
String [] paths;
int i=1;

AudioOutput output;
HighPassSP hpf;
LowPassSP lpf;

import ddf.minim.analysis.*;
import ddf.minim.*;



void setup () {
  background(0);
  size(810, 500, P3D);

  paths = new String[100];

  setupDeLista();

  play= new ControlP5(this);
  play.addButton("play").setPosition(10, 80).setSize(140, 70);
  pause= new ControlP5(this);
  pause.addButton("pause").setPosition(150, 80).setSize(140, 70);
  Volup= new ControlP5(this);
  Volup.addButton("up").setPosition(240, 160).setSize(50, 50);
  Voldown= new ControlP5(this);
  Voldown.addButton("down").setPosition(240, 210).setSize(50, 50);
  HPass= new ControlP5(this);
  HPass.addButton("HighPass").setPosition(10, 270).setSize(140, 50);
  LPass= new ControlP5(this);
  LPass.addButton("LowPass").setPosition(150, 270).setSize(140, 50);
  minim = new Minim(this);

}
void draw() {
  background(0);
  try {
    int timeleft=song.length()-song.position();
    meta = song.getMetaData();
    textSize(15);
    text("Title: "+meta.title(), 10, 170);
    text("Album: "+meta.album(), 10, 190);
    text("Author: "+meta.author(), 10, 210);
    text("Time left : "+timeleft, 10, 230);
  }
  catch(Exception e) {
  }
       noFill();
      try{fftLin.forward( song.mix );
      for (int i = 0; i < fftLin.specSize(); i++) {
        stroke(255);
        line(i, 500, i, 500 - fftLin.getBand(i)*2);
      }
    }catch(Exception e){}

}
public void play() {
  if (playing==false) {
    song.play();
    println("play"); 
    playing=true;
  }
}

public void pause() {
  song.pause();
  cancion.pause();
  println("stop");
  playing=false;
}
public void up() {
  song.setGain(volume+=3);
  println("Volume +");
}

public void down() {
  song.setGain(volume-=3);
  println("Volume -");
}

public void HighPass() {
  if (h==false) {
    song.pause();
    cancion.patch( hpf ).patch( output );
    cancion.play();
    h=true;
  } else {
    cancion.rewind();
    cancion.pause();
    h=false;
  }
}

public void LowPass() {
  if (l==false) {
    song.pause();
    cancion.patch( lpf ).patch( output );
    cancion.play();
    l=true;
  } else {
    cancion.rewind();
    cancion.pause();
    l=false;
  }
}

void setupDeLista() {
  cp5 = new ControlP5(this);

  // Configuracion basica para ElasticSearch en local
  Settings.Builder settings = Settings.settingsBuilder();
  // Esta carpeta se encontrara dentro de la carpeta del Processing
  settings.put("path.data", "esdata");
  settings.put("path.home", "/");
  settings.put("http.enabled", false);
  settings.put("index.number_of_replicas", 0);
  settings.put("index.number_of_shards", 1);

  // Inicializacion del nodo de ElasticSearch
  node = NodeBuilder.nodeBuilder()
    .settings(settings)
    .clusterName("mycluster")
    .data(true)
    .local(true)
    .node();

  // Instancia de cliente de conexion al nodo de ElasticSearch
  client = node.client();

  // Esperamos a que el nodo este correctamente inicializado
  ClusterHealthResponse r = client.admin().cluster().prepareHealth().setWaitForGreenStatus().get();
  println(r);

  // Revisamos que nuestro indice (base de datos) exista
  IndicesExistsResponse ier = client.admin().indices().prepareExists(INDEX_NAME).get();
  if (!ier.isExists()) {
    // En caso contrario, se crea el indice
    client.admin().indices().prepareCreate(INDEX_NAME).get();
  }

  // Agregamos a la vista un boton de importacion de archivos
  cp5.addButton("importFiles")
    .setPosition(10, 10)
    .setLabel("Importar archivos")
    .setSize(280, 60);

  // Agregamos a la vista una lista scrollable que mostrara las canciones
  list = cp5.addScrollableList("playlist")
    .setPosition(300, 10)
    .setSize(500, 400)
    .setBarHeight(20)
    .setItemHeight(20)
    .setType(ScrollableList.LIST);

  // Cargamos los archivos de la base de datos
  loadFiles();
}
void importFiles() {
  // Selector de archivos
  JFileChooser jfc = new JFileChooser();
  // Agregamos filtro para seleccionar solo archivos .mp3
  jfc.setFileFilter(new FileNameExtensionFilter("MP3 File", "mp3"));
  // Se permite seleccionar multiples archivos a la vez
  jfc.setMultiSelectionEnabled(true);
  // Abre el dialogo de seleccion
  jfc.showOpenDialog(null);

  // Iteramos los archivos seleccionados
  for (File f : jfc.getSelectedFiles()) {
    // Si el archivo ya existe en el indice, se ignora
    GetResponse response = client.prepareGet(INDEX_NAME, DOC_TYPE, f.getAbsolutePath()).setRefresh(true).execute().actionGet();
    if (response.isExists()) {
      continue;
    }

    // Cargamos el archivo en la libreria minim para extrar los metadatos
    Minim minim = new Minim(this);
    AudioPlayer song = minim.loadFile(f.getAbsolutePath());
    AudioMetaData meta = song.getMetaData();

    // Almacenamos los metadatos en un hashmap
    Map<String, Object> doc = new HashMap<String, Object>();
    doc.put("author", meta.author());
    doc.put("title", meta.title());
    doc.put("path", f.getAbsolutePath());

    try {
      // Le decimos a ElasticSearch que guarde e indexe el objeto
      client.prepareIndex(INDEX_NAME, DOC_TYPE, f.getAbsolutePath())
        .setSource(doc)
        .execute()
        .actionGet();

      // Agregamos el archivo a la lista
      addItem(doc);
    } 
    catch(Exception e) {
      e.printStackTrace();
    }
  }
}

// Al hacer click en algun elemento de la lista, se ejecuta este metodo
void playlist(int n) {
  println(list.getItem(n));
  path=paths[n+1];
  if (playing==false) {
    song = minim.loadFile(path, 1024);
    cancion= new FilePlayer( minim.loadFileStream(paths[n+1]));
    output = minim.getLineOut();
    hpf = new HighPassSP(1000, output.sampleRate());
    lpf = new LowPassSP(100, output.sampleRate());
    fftLin = new FFT( song.bufferSize(), song.sampleRate() );
  }
}

void loadFiles() {
  try {
    // Buscamos todos los documentos en el indice
    SearchResponse response = client.prepareSearch(INDEX_NAME).execute().actionGet();

    // Se itera los resultados
    for (SearchHit hit : response.getHits().getHits()) {
      // Cada resultado lo agregamos a la lista
      addItem(hit.getSource());
    }
  } 
  catch(Exception e) {
    e.printStackTrace();
  }
}

// Metodo auxiliar para no repetir codigo
void addItem(Map<String, Object> doc) {
  // Se agrega a la lista. El primer argumento es el texto a desplegar en la lista, el segundo es el objeto que queremos que almacene
  list.addItem(doc.get("author") + " - " + doc.get("title"), doc);
  paths[i]=doc.get("path")+"";
  i+=1;
}