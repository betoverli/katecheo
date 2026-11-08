#!/usr/bin/env node
/**
 * Generates ios/App/App/Localizable.xcstrings (+ InfoPlist.xcstrings) and
 * optionally rewrites Swift sources to wrap known UI strings in String(localized:).
 *
 * Usage:
 *   node scripts/generate-ios-l10n.mjs            # catalog only
 *   node scripts/generate-ios-l10n.mjs --rewrite  # catalog + wrap Swift UI strings
 */
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const appDir = path.join(root, "ios/App/App");
const rewrite = process.argv.includes("--rewrite");

function extractI18n() {
  const src = fs.readFileSync(path.join(root, "src/lib/i18n.ts"), "utf8");
  function extractLocale(locale) {
    const marker = `\n  ${locale}: {`;
    const start = src.indexOf(marker);
    if (start < 0) throw new Error(`no locale ${locale}`);
    let i = start + marker.length;
    let depth = 1;
    const bodyStart = i;
    while (i < src.length && depth > 0) {
      const c = src[i++];
      if (c === "{") depth++;
      else if (c === "}") depth--;
    }
    const body = src.slice(bodyStart, i - 1);
    const out = {};
    const keyRe =
      /^\s{4}([A-Za-z][A-Za-z0-9]*)\s*:\s*(?:"((?:\\.|[^"\\])*)"|`((?:\\.|[^`\\])*)`)/gm;
    let km;
    while ((km = keyRe.exec(body))) {
      out[km[1]] = (km[2] ?? km[3])
        .replace(/\\n/g, "\n")
        .replace(/\\"/g, '"')
        .replace(/\\'/g, "'");
    }
    return out;
  }
  return { pt: extractLocale("pt"), en: extractLocale("en"), es: extractLocale("es") };
}

const i18n = extractI18n();
/** @type {Map<string, {en: string, es: string}>} */
const translations = new Map();

for (const key of Object.keys(i18n.pt)) {
  const pt = i18n.pt[key];
  const en = i18n.en[key];
  const es = i18n.es[key];
  if (pt && en && es && !translations.has(pt)) {
    translations.set(pt, { en, es });
  }
}

/** Extra native-only strings (pt-BR source → en / es). */
const MANUAL = {
  OK: ["OK", "OK"],
  Erro: ["Error", "Error"],
  Cancelar: ["Cancel", "Cancelar"],
  Salvar: ["Save", "Guardar"],
  Criar: ["Create", "Crear"],
  Excluir: ["Delete", "Eliminar"],
  Fechar: ["Close", "Cerrar"],
  Pronto: ["Done", "Listo"],
  Atualizar: ["Refresh", "Actualizar"],
  Renomear: ["Rename", "Renombrar"],
  Entrar: ["Sign in", "Entrar"],
  Sair: ["Leave", "Salir"],
  "Buscar livro": ["Search book", "Buscar libro"],
  "Pesquisar notas": ["Search notes", "Buscar notas"],
  "Pesquisar notas do grupo": ["Search group notes", "Buscar notas del grupo"],
  "Pesquisar grupos": ["Search groups", "Buscar grupos"],
  "Buscar temas": ["Search themes", "Buscar temas"],
  "Novo grupo": ["New group", "Grupo nuevo"],
  "Nome do grupo": ["Group name", "Nombre del grupo"],
  "Criar (listado)": ["Create (listed)", "Crear (listado)"],
  "Criar (privado)": ["Create (private)", "Crear (privado)"],
  "Nome muito curto": ["Name too short", "Nombre demasiado corto"],
  "Use pelo menos 2 caracteres.": ["Use at least 2 characters.", "Usa al menos 2 caracteres."],
  "Não foi possível criar": ["Couldn’t create", "No se pudo crear"],
  "Renomear grupo": ["Rename group", "Renombrar grupo"],
  "Renomear grupo…": ["Rename group…", "Renombrar grupo…"],
  "Excluir grupo…": ["Delete group…", "Eliminar grupo…"],
  "Excluir grupo": ["Delete group", "Eliminar grupo"],
  "Esta ação remove o grupo e as publicações. Não dá para desfazer.": [
    "This removes the group and its posts. It can’t be undone.",
    "Esto elimina el grupo y las publicaciones. No se puede deshacer.",
  ],
  Listado: ["Listed", "Listado"],
  Privado: ["Private", "Privado"],
  " · pedido pendente": [" · pending request", " · solicitud pendiente"],
  "Faça login para ver seus grupos.": ["Sign in to see your groups.", "Inicia sesión para ver tus grupos."],
  "Nenhum grupo ainda.\nEntre para sincronizar.": [
    "No groups yet.\nSign in to sync.",
    "Todavía no hay grupos.\nEntra para sincronizar.",
  ],
  "Você ainda não tem grupos.\nCrie um com «Novo grupo».": [
    "You don’t have groups yet.\nCreate one with “New group”.",
    "Aún no tienes grupos.\nCrea uno con «Grupo nuevo».",
  ],
  "Nenhum resultado.": ["No results.", "Ningún resultado."],
  "Sessão expirada. Entre novamente.": ["Session expired. Sign in again.", "Sesión expirada. Entra de nuevo."],
  "Sessão expirada.": ["Session expired.", "Sesión expirada."],
  "Em breve nativo.": ["Coming soon natively.", "Pronto de forma nativa."],
  "Planos de leitura em breve nativo.\nOs outros separadores já estão no app.": [
    "Reading plans coming soon natively.\nThe other tabs are already in the app.",
    "Planes de lectura próximamente nativos.\nLas otras pestañas ya están en la app.",
  ],
  Leitura: ["Reading", "Lectura"],
  Temas: ["Themes", "Temas"],
  Listas: ["Lists", "Listas"],
  Categorias: ["Categories", "Categorías"],
  Categoria: ["Category", "Categoría"],
  Tema: ["Theme", "Tema"],
  "Capítulo inteiro": ["Whole chapter", "Capítulo entero"],
  "Inserir referência": ["Insert reference", "Insertar referencia"],
  "Toque para escolher · segundo toque define o intervalo": [
    "Tap to choose · second tap sets the range",
    "Toca para elegir · el segundo toque define el intervalo",
  ],
  "Link pronto": ["Link ready", "Enlace listo"],
  "Abrir na Bíblia": ["Open in Bible", "Abrir en la Biblia"],
  "Copiar referência": ["Copy reference", "Copiar referencia"],
  "Adicionar à nota de hoje": ["Add to today’s note", "Añadir a la nota de hoy"],
  "Adicionar tags": ["Add tags", "Añadir etiquetas"],
  "Nova tag": ["New tag", "Nueva etiqueta"],
  "Remover tag": ["Remove tag", "Quitar etiqueta"],
  "Salvar na minha lista": ["Save to my list", "Guardar en mi lista"],
  "Salvar na lista": ["Save to list", "Guardar en la lista"],
  "Sem link": ["No link", "Sin enlace"],
  "Não foi possível montar o link da Bíblia.": [
    "Couldn’t build the Bible link.",
    "No se pudo armar el enlace de la Biblia.",
  ],
  "Abrir nota": ["Open note", "Abrir nota"],
  "Não foi possível adicionar": ["Couldn’t add", "No se pudo añadir"],
  "Não foi possível salvar": ["Couldn’t save", "No se pudo guardar"],
  "Minha lista": ["My list", "Mi lista"],
  "Nova lista…": ["New list…", "Lista nueva…"],
  "Nova lista": ["New list", "Lista nueva"],
  "Nome da lista": ["List name", "Nombre de la lista"],
  "Minhas listas": ["My lists", "Mis listas"],
  Nova: ["New", "Nueva"],
  "Nenhuma lista ainda.": ["No lists yet.", "Todavía no hay listas."],
  "Salve um versículo em «Salvar na minha lista».": [
    "Save a verse with “Save to my list”.",
    "Guarda un versículo en «Guardar en mi lista».",
  ],
  "Inicie sessão na aba Perfil ou Caderno para salvar versículos.": [
    "Sign in from Profile or Notebook to save verses.",
    "Inicia sesión en Perfil o Cuaderno para guardar versículos.",
  ],
  "Inicie sessão para ver suas listas de versículos.": [
    "Sign in to see your verse lists.",
    "Inicia sesión para ver tus listas de versículos.",
  ],
  "Nenhum tema encontrado.": ["No themes found.", "No se encontraron temas."],
  "Não foi possível carregar.": ["Couldn’t load.", "No se pudo cargar."],
  "Faça login para ver as notas do grupo.": [
    "Sign in to see group notes.",
    "Inicia sesión para ver las notas del grupo.",
  ],
  "Entre para sincronizar este grupo.": [
    "Sign in to sync this group.",
    "Entra para sincronizar este grupo.",
  ],
  "Faça login para sincronizar o caderno.": [
    "Sign in to sync the notebook.",
    "Inicia sesión para sincronizar el cuaderno.",
  ],
  "Offline / sem sessão — cache local.": [
    "Offline / no session — local cache.",
    "Sin conexión / sin sesión — caché local.",
  ],
  "Nenhuma nota ainda.\nEntre para ver seu caderno.": [
    "No notes yet.\nSign in to see your notebook.",
    "Todavía no hay notas.\nEntra para ver tu cuaderno.",
  ],
  "Nenhuma nota ainda.\nToque em + para criar a primeira.": [
    "No notes yet.\nTap + to create the first one.",
    "Todavía no hay notas.\nToca + para crear la primera.",
  ],
  "Nenhuma nota neste grupo.": ["No notes in this group.", "No hay notas en este grupo."],
  Retirar: ["Remove", "Quitar"],
  "Retirar do grupo": ["Remove from group", "Quitar del grupo"],
  "Retirar esta nota do grupo?": ["Remove this note from the group?", "¿Quitar esta nota del grupo?"],
  "Excluir esta nota?": ["Delete this note?", "¿Eliminar esta nota?"],
  "Excluir nota": ["Delete note", "Eliminar nota"],
  "Speakers…": ["Speakers…", "Speakers…"],
  "Novo speaker": ["New speaker", "Speaker nuevo"],
  Nenhum: ["None", "Ninguno"],
  "Carregando…": ["Loading…", "Cargando…"],
  "Status da nota": ["Note status", "Estado de la nota"],
  "Editor nativo": ["Native editor", "Editor nativo"],
  "Editor": ["Editor", "Editor"],
  "Editor sempre claro": ["Keep editor in Light", "Editor siempre claro"],
  "Manter a edição de notas no modo Claro": ["Keep note editing in Light mode", "Mantener la edición de notas en modo Claro"],
  "Só enquanto edita uma nota. O restante do app segue a Aparência.": ["Only while editing a note. The rest of the app follows Appearance.", "Solo mientras editas una nota. El resto de la app sigue Apariencia."],
  "Não lido": ["Unread", "No leído"],
  "Amigos": ["Friends", "Amigos"],
  "Pedidos e aceites": ["Requests and acceptances", "Solicitudes y aceptaciones"],
  "Atividade nova": ["New activity", "Actividad nueva"],
  "Pedidos pendentes": ["Pending requests", "Solicitudes pendientes"],
  "Aceites recentes": ["Recent acceptances", "Aceptaciones recientes"],
  "Nenhum pedido pendente": ["No pending requests", "Ninguna solicitud pendiente"],
  "Quando alguém te enviar um pedido, ele aparece aqui.": ["When someone sends you a request, it appears here.", "Cuando alguien te envíe una solicitud, aparece aquí."],
  "Pedido de amizade": ["Friend request", "Solicitud de amistad"],
  "Pendente — aguardando API nativa": ["Pending — waiting for native API", "Pendiente — esperando API nativa"],
  "Nenhum aceite recente": ["No recent acceptances", "Ninguna aceptación reciente"],
  "Amizade aceita": ["Friendship accepted", "Amistad aceptada"],
  "Aceitar ou recusar pedidos ainda não está disponível neste app iOS — falta a API nativa de amigos.": ["Accepting or declining requests is not available in this iOS app yet — the native friends API is missing.", "Aceptar o rechazar solicitudes aún no está disponible en esta app iOS — falta la API nativa de amigos."],
  "Dispensar aviso": ["Dismiss reminder", "Descartar aviso"],
  "Dispensar aviso de leitura": ["Dismiss reading reminder", "Descartar aviso de lectura"],
  "Caderno com itens não lidos": ["Notebook has unread items", "Cuaderno con elementos no leídos"],
  "Grupos com atividade não lida": ["Groups have unread activity", "Grupos con actividad no leída"],
  "Ferramentas com leitura pendente": ["Tools have pending reading", "Herramientas con lectura pendiente"],
  "Perfil com pedidos de amizade": ["Profile has friend activity", "Perfil con actividad de amistad"],

  "Nota sincronizada": ["Note synced", "Nota sincronizada"],
  "Link da Bíblia indisponível": ["Bible link unavailable", "Enlace de Biblia no disponible"],
  "Salvando…": ["Saving…", "Guardando…"],
  Salvo: ["Saved", "Guardado"],
  "Sessão expirada — alteração guardada no aparelho.": [
    "Session expired — change saved on this device.",
    "Sesión expirada — cambio guardado en el dispositivo.",
  ],
  "Salvo no aparelho — sincroniza quando houver rede.": [
    "Saved on device — syncs when you’re online.",
    "Guardado en el dispositivo — se sincroniza cuando haya red.",
  ],
  Configurações: ["Settings", "Configuración"],
  "Mover para grupo…": ["Move to group…", "Mover al grupo…"],
  "Mover para grupo": ["Move to group", "Mover al grupo"],
  "Sem grupos": ["No groups", "Sin grupos"],
  "Crie ou entre em um grupo na aba Grupos.": [
    "Create or join a group in the Groups tab.",
    "Crea o entra a un grupo en la pestaña Grupos.",
  ],
  "Corpo da nota": ["Note body", "Cuerpo de la nota"],
  "A primeira linha é o título": ["The first line is the title", "La primera línea es el título"],
  Numerada: ["Numbered", "Numerada"],
  Checklist: ["Checklist", "Checklist"],
  Citação: ["Quote", "Cita"],
  Sublinhado: ["Underline", "Subrayado"],
  Riscado: ["Strikethrough", "Tachado"],
  "Referência bíblica": ["Bible reference", "Referencia bíblica"],
  Desfazer: ["Undo", "Deshacer"],
  Refazer: ["Redo", "Rehacer"],
  "Toque para remover": ["Tap to remove", "Toca para quitar"],
  "Nome e contato": ["Name and contact", "Nombre y contacto"],
  usuario: ["username", "usuario"],
  Email: ["Email", "Correo"],
  Senha: ["Password", "Contraseña"],
  Aparência: ["Appearance", "Apariencia"],
  Sistema: ["System", "Sistema"],
  Claro: ["Light", "Claro"],
  Escuro: ["Dark", "Oscuro"],
  "A aparência se aplica às telas nativas. O tema fica salvo na sua conta.": [
    "Appearance applies to native screens. The theme is saved to your account.",
    "La apariencia se aplica a las pantallas nativas. El tema se guarda en tu cuenta.",
  ],
  Aplicativo: ["App", "Aplicación"],
  Abertura: ["Open with", "Apertura"],
  "Preferir o app": ["Prefer the app", "Preferir la app"],
  "Preferir a web": ["Prefer the web", "Preferir la web"],
  Avisos: ["Alerts", "Avisos"],
  Dispositivo: ["Device", "Dispositivo"],
  "Tipos de alerta": ["Alert types", "Tipos de alerta"],
  "Este dispositivo pode receber notificações push (APNs).": [
    "This device can receive push notifications (APNs).",
    "Este dispositivo puede recibir notificaciones push (APNs).",
  ],
  "Ative as notificações nas Configurações do iOS se quiser alertas push.": [
    "Turn on notifications in iOS Settings if you want push alerts.",
    "Activa las notificaciones en Ajustes de iOS si quieres alertas push.",
  ],
  "Ativar push neste iPhone": ["Enable push on this iPhone", "Activar push en este iPhone"],
  "Toque para pedir permissão": ["Tap to request permission", "Toca para pedir permiso"],
  Notificações: ["Notifications", "Notificaciones"],
  "Permissão negada. Ative nas Configurações do iOS se quiser alertas.": [
    "Permission denied. Enable it in iOS Settings if you want alerts.",
    "Permiso denegado. Actívalo en Ajustes de iOS si quieres alertas.",
  ],
  "Lembretes dos seus planos": ["Reminders for your plans", "Recordatorios de tus planes"],
  "Pedidos e aceitações": ["Requests and acceptances", "Solicitudes y aceptaciones"],
  Compartilhamentos: ["Shares", "Compartidos"],
  "Notas e coleções compartilhadas": [
    "Shared notes and collections",
    "Notas y colecciones compartidas",
  ],
  "Atividade nos seus grupos": ["Activity in your groups", "Actividad en tus grupos"],
  Preferências: ["Preferences", "Preferencias"],
  "Google, Apple ou email": ["Google, Apple, or email", "Google, Apple o correo"],
  "Configurar alertas": ["Configure alerts", "Configurar alertas"],
  "Sobre e ajuda": ["About & help", "Acerca de y ayuda"],
  "Privacidade · site": ["Privacy · website", "Privacidad · sitio"],
  "Sair da conta": ["Sign out", "Cerrar sesión"],
  "Baixar meus dados": ["Download my data", "Descargar mis datos"],
  "Excluir conta": ["Delete account", "Eliminar cuenta"],
  "Sair da conta?": ["Sign out?", "¿Cerrar sesión?"],
  "Você vai sair desta conta neste dispositivo.": [
    "You’ll sign out of this account on this device.",
    "Vas a salir de esta cuenta en este dispositivo.",
  ],
  "Excluir conta?": ["Delete account?", "¿Eliminar cuenta?"],
  "Isso remove permanentemente suas notas, grupos e preferências. Não pode ser desfeito.": [
    "This permanently removes your notes, groups, and preferences. It can’t be undone.",
    "Esto elimina permanentemente tus notas, grupos y preferencias. No se puede deshacer.",
  ],
  "Conta apagada": ["Account deleted", "Cuenta eliminada"],
  "Sua conta foi removida.": ["Your account was removed.", "Tu cuenta fue eliminada."],
  "Sem nome": ["No name", "Sin nombre"],
  "Defina um @usuário": ["Set a @username", "Define un @usuario"],
  "Conta Verse2Note": ["Verse2Note account", "Cuenta Verse2Note"],
  "Entre para ver seu perfil.": ["Sign in to see your profile.", "Entra para ver tu perfil."],
  "Entre para ver seu caderno.": ["Sign in to see your notebook.", "Entra para ver tu cuaderno."],
  "Entrar com email": ["Sign in with email", "Entrar con correo"],
  "Abrindo Google…": ["Opening Google…", "Abriendo Google…"],
  "Apple…": ["Apple…", "Apple…"],
  "Preencha email e senha.": ["Enter email and password.", "Completa correo y contraseña."],
  "Entrando…": ["Signing in…", "Entrando…"],
  "Sessão iniciada.": ["Signed in.", "Sesión iniciada."],
  "Resposta inválida.": ["Invalid response.", "Respuesta no válida."],
  "Sem resposta.": ["No response.", "Sin respuesta."],
  "Sem texto": ["No text", "Sin texto"],
  Membro: ["Member", "Miembro"],
  "Não foi possível abrir o login Google.": [
    "Couldn’t open Google sign-in.",
    "No se pudo abrir el inicio con Google.",
  ],
  "Login Google cancelado ou falhou.": [
    "Google sign-in canceled or failed.",
    "Inicio con Google cancelado o falló.",
  ],
  "Código de login em falta.": ["Sign-in code missing.", "Falta el código de inicio."],
  "Falha ao obter sessão.": ["Failed to get session.", "No se pudo obtener la sesión."],
  "Email ou senha incorretos.": ["Incorrect email or password.", "Correo o contraseña incorrectos."],
  "Falha no login.": ["Sign-in failed.", "Error al iniciar sesión."],
  "Login cancelado.": ["Sign-in canceled.", "Inicio cancelado."],
  "URL de login inválida.": ["Invalid sign-in URL.", "URL de inicio no válida."],
  "Token Apple em falta.": ["Apple token missing.", "Falta el token de Apple."],
  "Sign in with Apple ainda não está configurado no servidor.": [
    "Sign in with Apple isn’t configured on the server yet.",
    "Sign in with Apple aún no está configurado en el servidor.",
  ],
  "Falha no login Apple.": ["Apple sign-in failed.", "Error al iniciar con Apple."],
  Interface: ["Interface", "Interfaz"],
  "O idioma da interface segue o do iPhone. Para mudar, abra as Configurações do app e escolha Português (Brasil), English ou Español.": [
    "The interface language follows your iPhone. To change it, open the app’s Settings and choose Portuguese (Brazil), English, or Español.",
    "El idioma de la interfaz sigue el del iPhone. Para cambiarlo, abre Ajustes de la app y elige Português (Brasil), English o Español.",
  ],
  "Abrir Configurações do idioma": ["Open language Settings", "Abrir Ajustes de idioma"],
  "Idioma da interface": ["Interface language", "Idioma de la interfaz"],
  "Segue o idioma do iPhone": ["Follows iPhone language", "Sigue el idioma del iPhone"],
  "Menus, botões e telas seguem o idioma do iPhone (ou o idioma por app em Ajustes).": [
    "Menus, buttons, and screens follow your iPhone language (or the per-app language in Settings).",
    "Menús, botones y pantallas siguen el idioma del iPhone (o el idioma por app en Ajustes).",
  ],
  // Format / interpolated templates (catalog keys use %@)
  "Sem rede. %@": ["No network. %@", "Sin red. %@"],
  "Sem rede — mostrando cache%@.": ["No network — showing cache%@.", "Sin red — mostrando caché%@."],
  " · %lld pendente(s)": [" · %lld pending", " · %lld pendiente(s)"],
  "%lld grupos · sincronizado": ["%lld groups · synced", "%lld grupos · sincronizado"],
  "%lld notas · sincronizado": ["%lld notes · synced", "%lld notas · sincronizado"],
  "%lld notas no grupo · sincronizado": [
    "%lld notes in group · synced",
    "%lld notas en el grupo · sincronizado",
  ],
  "%lld membros · %@%@": ["%lld members · %@%@", "%lld miembros · %@%@"],
  "%lld livros · Bíblia: %@": ["%lld books · Bible: %@", "%lld libros · Biblia: %@"],
  "Não foi possível carregar. %@": ["Couldn’t load. %@", "No se pudo cargar. %@"],
  "Cache local · %@": ["Local cache · %@", "Caché local · %@"],
  "Não abriu a Bíblia: %@": ["Couldn’t open the Bible: %@", "No se abrió la Biblia: %@"],
  "Link indisponível: %@": ["Link unavailable: %@", "Enlace no disponible: %@"],
  "Copiado: %@": ["Copied: %@", "Copiado: %@"],
  "Adicionado à nota: %@": ["Added to note: %@", "Añadido a la nota: %@"],
  "%@ foi inserido como referência (bibleRef).": [
    "%@ was inserted as a reference (bibleRef).",
    "%@ se insertó como referencia (bibleRef).",
  ],
  "Salvo em «%@»": ["Saved in “%@”", "Guardado en «%@»"],
  "Excluir «%@»?": ["Delete “%@”?", "¿Eliminar «%@»?"],
  "Retirada de «%@»": ["Removed from “%@”", "Quitada de «%@»"],
  "Movida para «%@»": ["Moved to “%@”", "Movida a «%@»"],
  "Nota de %@. Só o autor pode editar nesta tela nativa.": [
    "Note by %@. Only the author can edit on this native screen.",
    "Nota de %@. Solo el autor puede editar en esta pantalla nativa.",
  ],
  "Registrado (%lld)": ["Registered (%lld)", "Registrado (%lld)"],
  "%lld dispositivo(s)": ["%lld device(s)", "%lld dispositivo(s)"],
  "%lld temas": ["%lld themes", "%lld temas"],
  "%lld versículos": ["%lld verses", "%lld versículos"],
  "Capítulo %lld": ["Chapter %lld", "Capítulo %lld"],
  "Versículo %lld": ["Verse %lld", "Versículo %lld"],
  "%@ · %lld capítulos": ["%@ · %lld chapters", "%@ · %lld capítulos"],
  "Toque no versículo final (início: %lld)": [
    "Tap the end verse (start: %lld)",
    "Toca el versículo final (inicio: %lld)",
  ],
  "HTTP %lld: %@": ["HTTP %lld: %@", "HTTP %lld: %@"],
  Membros: ["Members", "Miembros"],
  Convidar: ["Invite", "Invitar"],
  "Convidar…": ["Invite…", "Invitar…"],
  Pedidos: ["Requests", "Solicitudes"],
  Aceitar: ["Accept", "Aceptar"],
  Recusar: ["Decline", "Rechazar"],
  "Tornar membro": ["Make member", "Hacer miembro"],
  "Tornar admin": ["Make admin", "Hacer admin"],
  "Remover do grupo": ["Remove from group", "Quitar del grupo"],
  "Sair do grupo": ["Leave group", "Salir del grupo"],
  pendente: ["pending", "pendiente"],
  admin: ["admin", "admin"],
  Offline: ["Offline", "Sin conexión"],
  "Offline — mostrando grupos em cache.": [
    "Offline — showing cached groups.",
    "Sin conexión — mostrando grupos en caché.",
  ],
  "Entre no grupo «%@» no Verse2Note": [
    "Join the “%@” group on Verse2Note",
    "Únete al grupo «%@» en Verse2Note",
  ],
  "Tentar de novo": ["Try again", "Intentar de nuevo"],
  "Puxe para atualizar quando a rede voltar.": [
    "Pull to refresh when you’re back online.",
    "Desliza para actualizar cuando vuelva la red.",
  ],
};

for (const [pt, [en, es]] of Object.entries(MANUAL)) {
  translations.set(pt, { en, es });
}

const SKIP_FILES = new Set([
  "NoteDocumentCodec.swift",
  "LegacyNoteConverter.swift",
  "LegacyWebStorageImporter.swift",
  "LocalNoteCache.swift",
  "NativeOutbox.swift",
  "NativeShellMode.swift",
  "KeychainStore.swift",
  "AppRoot.swift",
  "NativeDeepLinkRouter.swift",
  "NativeSessionBootstrap.swift",
  "NativePushService.swift",
  "V2NDesign.swift",
  "AppDelegate.swift",
  "SceneDelegate.swift",
]);

const NEVER_WRAP = new Set([
  "init(coder:) has not been implemented",
  "Default Configuration",
  "spin",
  "transform.rotation.z",
  "V2NNoteRowCell",
  "V2NGroupRowCell",
  "GroupCell",
  "SubtitleNoteCell",
  "field",
  "theme",
  "lang",
  "bible",
  "notify",
  "cell",
  "yyyy-MM-dd",
  "en_US_POSIX",
  "verse2note-dados.json",
  "https://verse2note.com/about",
  "n/",
  "  ·  ",
  "@ ",
  "^@+",
  "system",
  "light",
  "dark",
  "pt",
  "en",
  "es",
  "locale",
  "copyLocale",
  "appId",
  "translationId",
  "preferNative",
  "firstName",
  "lastName",
  "handle",
  "profileEmail",
  "reading",
  "friends",
  "shares",
  "groups",
  "listed",
  "pending",
  "youversion",
  "Bearer ",
]);

function looksLikeUiString(s) {
  if (!s || s.length < 1) return false;
  if (NEVER_WRAP.has(s)) return false;
  if (s.startsWith("http") || s.startsWith("com.")) return false;
  if (s.includes("/") && !s.includes(" ")) return false;
  if (/^[a-z][a-zA-Z0-9_.]*$/.test(s) && !["OK"].includes(s)) return false;
  if (/^[A-Z][a-z]+[A-Z]/.test(s) && !s.includes(" ")) return false; // camel identifiers
  // Must have a letter
  if (!/[A-Za-zÀ-ÿ]/.test(s)) return false;
  // Pure SF Symbol-ish
  if (/^[a-z0-9.]+$/.test(s) && s.includes(".")) return false;
  return true;
}

function unit(value) {
  return { stringUnit: { state: "translated", value } };
}

function buildCatalog(extraKeys = []) {
  const strings = {};
  const keys = new Set([...translations.keys(), ...extraKeys]);
  for (const key of [...keys].sort((a, b) => a.localeCompare(b, "pt-BR"))) {
    const tr = translations.get(key);
    if (!tr) continue;
    strings[key] = {
      extractionState: "manual",
      localizations: {
        "pt-BR": unit(key.includes("%") ? key : key),
        en: unit(tr.en),
        es: unit(tr.es),
      },
    };
  }
  return {
    sourceLanguage: "pt-BR",
    strings,
    version: "1.0",
  };
}

function writeJson(filePath, obj) {
  fs.writeFileSync(filePath, `${JSON.stringify(obj, null, 2)}\n`);
}

const catalogPath = path.join(appDir, "Localizable.xcstrings");
const infoPlistCatalogPath = path.join(appDir, "InfoPlist.xcstrings");

const infoPlistCatalog = {
  sourceLanguage: "pt-BR",
  strings: {
    CFBundleDisplayName: {
      extractionState: "manual",
      localizations: {
        "pt-BR": unit("Verse2Note"),
        en: unit("Verse2Note"),
        es: unit("Verse2Note"),
      },
    },
    CFBundleName: {
      extractionState: "manual",
      localizations: {
        "pt-BR": unit("Verse2Note"),
        en: unit("Verse2Note"),
        es: unit("Verse2Note"),
      },
    },
    NSUserTrackingUsageDescription: {
      extractionState: "manual",
      comment: "Reserved; app does not request tracking. Kept for InfoPlist completeness.",
      localizations: {
        "pt-BR": unit("O Verse2Note não rastreia você entre apps ou sites."),
        en: unit("Verse2Note does not track you across apps or websites."),
        es: unit("Verse2Note no te rastrea entre apps o sitios."),
      },
    },
  },
  version: "1.0",
};

writeJson(catalogPath, buildCatalog());
writeJson(infoPlistCatalogPath, infoPlistCatalog);
console.log(
  `Wrote ${path.relative(root, catalogPath)} with ${Object.keys(JSON.parse(fs.readFileSync(catalogPath, "utf8")).strings).length} keys`,
);

if (!rewrite) {
  process.exit(0);
}

/** Wrap plain `"…"` literals that match known UI strings. */
function wrapFile(filePath) {
  let src = fs.readFileSync(filePath, "utf8");
  const original = src;
  // Longest keys first to avoid partial issues
  const keys = [...translations.keys()].sort((a, b) => b.length - a.length);
  for (const key of keys) {
    if (!looksLikeUiString(key)) continue;
    if (key.includes("%")) continue; // format templates applied manually
    if (key.includes("\n")) {
      // Swift may use "a\nb" escaped
      const escaped = key.replace(/\n/g, "\\n").replace(/"/g, '\\"');
      const needle = `"${escaped}"`;
      const replacement = `String(localized: "${escaped}")`;
      src = replaceBareStringLiteral(src, needle, replacement);
      continue;
    }
    const escaped = key.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    const needle = `"${escaped}"`;
    const replacement = `String(localized: "${escaped}")`;
    src = replaceBareStringLiteral(src, needle, replacement);
  }
  if (src !== original) {
    fs.writeFileSync(filePath, src);
    return true;
  }
  return false;
}

function replaceBareStringLiteral(src, needle, replacement) {
  let out = "";
  let i = 0;
  while (i < src.length) {
    const idx = src.indexOf(needle, i);
    if (idx < 0) {
      out += src.slice(i);
      break;
    }
    const before = src.slice(Math.max(0, idx - 40), idx);
    // Skip if already wrapped / part of String(localized: / NSLocalizedString / comment
    if (
      /String\s*\(\s*localized\s*:\s*$/.test(before) ||
      /NSLocalizedString\s*\(\s*$/.test(before) ||
      /LocalizedStringResource\s*\(\s*$/.test(before) ||
      /\/\/.*$/.test(before.split("\n").pop() || "")
    ) {
      out += src.slice(i, idx + needle.length);
      i = idx + needle.length;
      continue;
    }
    // Skip dictionary keys in patches like ["locale": ...] when needle is short id — handled by NEVER_WRAP
    out += src.slice(i, idx) + replacement;
    i = idx + needle.length;
  }
  return out;
}

let changed = 0;
for (const name of fs.readdirSync(appDir)) {
  if (!name.endsWith(".swift")) continue;
  if (SKIP_FILES.has(name)) continue;
  if (name === "AppLocale.swift") continue;
  const fp = path.join(appDir, name);
  if (wrapFile(fp)) {
    changed++;
    console.log(`rewrote ${name}`);
  }
}
console.log(`Rewrote ${changed} Swift files`);
