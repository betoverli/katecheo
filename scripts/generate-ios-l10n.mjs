#!/usr/bin/env node
/**
 * Generates ios/App/Katecheo/Localizable.xcstrings (+ InfoPlist.xcstrings) and
 * optionally rewrites Swift sources to wrap known UI strings in String(localized:).
 *
 * Merge-only for Localizable.xcstrings: existing keys and translations are NEVER
 * deleted or overwritten. The script only adds missing keys from MANUAL / i18n.
 * Hand-edited catalog entries (e.g. from recent PRs) always win.
 *
 * Usage:
 *   node scripts/generate-ios-l10n.mjs            # catalog only (merge)
 *   node scripts/generate-ios-l10n.mjs --rewrite  # catalog + wrap Swift UI strings
 */
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const appDir = path.join(root, "ios/App/Katecheo");
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
  "screenshot.profile.firstName": ["Ana","Ana"],
  "screenshot.profile.lastName": ["Ribeiro","Ribeiro"],
  "screenshot.speaker.pastor": ["Pastor Mark","Pr. Marcos"],
  "screenshot.speaker.self": ["Me","Yo"],
  "screenshot.note.editor.title": ["Sermon prep — John 15","Preparación — Juan 15"],
  "screenshot.note.editor.h1": ["Abide in the vine","Permanecer en la vid"],
  "screenshot.note.editor.intro": ["Morning’s main text:","Texto central de la mañana:"],
  "screenshot.note.editor.h2": ["Sermon outline","Puntos del sermón"],
  "screenshot.note.editor.b1": ["The true vine — union with Christ","La vid verdadera — unión con Cristo"],
  "screenshot.note.editor.b2": ["The Father’s pruning — purposeful growth","La poda del Padre — crecimiento con propósito"],
  "screenshot.note.editor.b3": ["Apart from Him we can do nothing:","Sin Él nada podemos:"],
  "screenshot.note.editor.h3": ["Pastoral application","Aplicación pastoral"],
  "screenshot.note.editor.close": ["Fruit of the Spirit this week:","Fruto del Espíritu esta semana:"],
  "screenshot.note.sermon.title": ["Sermon — Peace that guards","Sermón — Paz que guarda"],
  "screenshot.note.sermon.body": ["Outline for Sunday’s service. Reference:","Esbozo para el culto del domingo. Referencia:"],
  "screenshot.note.devotion.title": ["Morning devotion","Devocional matutino"],
  "screenshot.note.devotion.body": ["The Lord is my shepherd. Passage:","El Señor es mi pastor. Pasaje:"],
  "screenshot.note.group.title": ["Small group study — Fellowship","Estudio del grupo — Comunión"],
  "screenshot.note.group.body": ["Questions for this week’s cell group. Text:","Preguntas para la célula de esta semana. Texto:"],
  "screenshot.tag.sermon": ["sermon","sermón"],
  "screenshot.tag.prep": ["prep","preparación"],
  "screenshot.tag.sunday": ["sunday","domingo"],
  "screenshot.tag.devotion": ["devotion","devocional"],
  "screenshot.tag.group": ["group","grupo"],
  "screenshot.tag.study": ["study","estudio"],
  "screenshot.group.cell.name": ["North Cell Group","Célula Norte"],
  "screenshot.group.cell.desc": ["Weekly study and family prayer","Estudio semanal y oración en familia"],
  "screenshot.group.leaders.name": ["Worship leadership","Liderazgo de alabanza"],
  "screenshot.group.leaders.desc": ["Rehearsals and service prep","Ensayos y preparación del culto"],
  "screenshot.member.2.first": ["Peter","Pedro"],
  "screenshot.member.2.last": ["Moore","Mora"],
  "screenshot.member.3.first": ["Sophia","Sofía"],
  "screenshot.member.3.last": ["Lane","Lima"],
  "screenshot.member.4.first": ["Luke","Lucas"],
  "screenshot.member.4.last": ["Allen","Álvarez"],
  "screenshot.list.psalms": ["Memorization — Psalms","Memorización — Salmos"],
  "screenshot.list.sermon": ["Sermon references","Referencias del sermón"],
  "screenshot.list.quarter": ["Quarterly studies","Estudios del trimestre"],
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
  // Keep in sync with hand-maintained catalog (Sign out, not "Leave group").
  Sair: ["Sign out", "Cerrar sesión"],
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
  Ferramentas: ["Tools", "Herramientas"],
  "Buscar planos": ["Search plans", "Buscar planes"],
  Capítulos: ["Chapters", "Capítulos"],
  Novo: ["New", "Nuevo"],
  Dias: ["Days", "Días"],
  Progresso: ["Progress", "Progreso"],
  "Planos de leitura": ["Reading plans", "Planes de lectura"],
  "Plano de leitura": ["Reading plan", "Plan de lectura"],
  "Criar tema": ["Create theme", "Crear tema"],
  "Criar lista": ["Create list", "Crear lista"],
  "Novo tema": ["New theme", "Tema nuevo"],
  "Nome do tema": ["Theme name", "Nombre del tema"],
  "Não foi possível carregar": ["Couldn't load", "No se pudo cargar"],
  "Tentar de novo": ["Try again", "Intentar de nuevo"],
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
  "Conta Katecheo": ["Katecheo account", "Cuenta Katecheo"],
  "Entre para ver seu perfil.": ["Sign in to see your profile.", "Entra para ver tu perfil."],
  "Entre para ver seu caderno.": ["Sign in to see your notebook.", "Entra para ver tu cuaderno."],
  "Entrar com email": ["Sign in with email", "Entrar con correo"],
  "Entrar ou criar conta": [
    "Sign in or create account",
    "Inicia sesión o crea una cuenta",
  ],
  "Na primeira vez, criamos sua conta automaticamente.": [
    "If you don’t have an account yet, we create one on first use.",
    "Si aún no tienes cuenta, la creamos en el primer uso.",
  ],
  "Google e Apple criam a conta no primeiro acesso.": [
    "Google and Apple create your account on first access.",
    "Google y Apple crean tu cuenta en el primer acceso.",
  ],
  "Criar conta": ["Create account", "Crear cuenta"],
  "Criar conta com email": ["Create account with email", "Crear cuenta con correo"],
  "Confirmar senha": ["Confirm password", "Confirmar contraseña"],
  "Senha (mín. 8)": ["Password (min. 8)", "Contraseña (mín. 8)"],
  "Informe seu nome.": ["Enter your name.", "Escribe tu nombre."],
  "Informe um email válido.": ["Enter a valid email.", "Introduce un correo válido."],
  "Informe sua senha.": ["Enter your password.", "Introduce tu contraseña."],
  "A senha deve ter pelo menos 8 caracteres.": [
    "Password must be at least 8 characters.",
    "La contraseña debe tener al menos 8 caracteres.",
  ],
  "As senhas não coincidem.": ["Passwords do not match.", "Las contraseñas no coinciden."],
  "Criando conta…": ["Creating account…", "Creando cuenta…"],
  "Este email já tem conta. Entre com a senha ou use Google/Apple.": [
    "This email already has an account. Sign in with your password or use Google/Apple.",
    "Este correo ya tiene cuenta. Entra con tu contraseña o usa Google/Apple.",
  ],
  "Não foi possível criar a conta.": [
    "Couldn’t create the account.",
    "No se pudo crear la cuenta.",
  ],
  "Muitas tentativas. Aguarde um momento.": [
    "Too many attempts. Please wait a moment.",
    "Demasiados intentos. Espera un momento.",
  ],
  // Contas conectadas (Profile → Account)
  "Contas conectadas": ["Connected sign-ins", "Cuentas conectadas"],
  "Conectar": ["Connect", "Conectar"],
  Apple: ["Apple", "Apple"],
  Google: ["Google", "Google"],
  "Email e senha": ["Email and password", "Correo y contraseña"],
  "Métodos de entrada": ["Sign-in methods", "Métodos de acceso"],
  Desligar: ["Disconnect", "Desconectar"],
  "Desligar método?": ["Disconnect this method?", "¿Desconectar este método?"],
  "Não é possível desligar": ["Can't disconnect", "No se puede desconectar"],
  "Alterar senha": ["Change password", "Cambiar contraseña"],
  "Definir senha": ["Set password", "Definir contraseña"],
  "Senha atual": ["Current password", "Contraseña actual"],
  "Nova senha": ["New password", "Nueva contraseña"],
  Atenção: ["Notice", "Aviso"],
  "Essa conta Apple já está ligada a outra conta Katecheo.": [
    "That Apple account is already linked to another Katecheo account.",
    "Esa cuenta de Apple ya está vinculada a otra cuenta Katecheo.",
  ],
  "Essa conta Google já está ligada a outra conta Katecheo.": [
    "That Google account is already linked to another Katecheo account.",
    "Esa cuenta de Google ya está vinculada a otra cuenta Katecheo.",
  ],
  "Mantenha pelo menos um método de entrada.": [
    "Keep at least one sign-in method.",
    "Mantén al menos un método de acceso.",
  ],
  "Apple, Google, email e senha": [
    "Apple, Google, email and password",
    "Apple, Google, correo y contraseña",
  ],
  "Ligue Apple, Google ou email e senha à mesma conta Katecheo. Mantenha pelo menos um método.": [
    "Link Apple, Google, or email and password to the same Katecheo account. Keep at least one method.",
    "Vincula Apple, Google o correo y contraseña a la misma cuenta Katecheo. Mantén al menos un método.",
  ],
  "Informe a senha atual para alterar.": [
    "Enter your current password to change it.",
    "Introduce la contraseña actual para cambiarla.",
  ],
  "Senha atual incorreta.": ["Current password is incorrect.", "La contraseña actual es incorrecta."],
  "Adicione um email no perfil antes de criar uma senha.": [
    "Add an email in your profile before creating a password.",
    "Añade un correo en tu perfil antes de crear una contraseña.",
  ],
  "Este método não está conectado.": [
    "This method isn’t connected.",
    "Este método no está conectado.",
  ],
  "Não foi possível atualizar as contas conectadas.": [
    "Couldn’t update connected sign-ins.",
    "No se pudieron actualizar las cuentas conectadas.",
  ],
  "Não foi possível ligar este método.": [
    "Couldn’t link this method.",
    "No se pudo vincular este método.",
  ],
  "Você poderá ligar de novo depois. Mantenha pelo menos um método de entrada.": [
    "You can connect it again later. Keep at least one sign-in method.",
    "Podrás vincularlo de nuevo después. Mantén al menos un método de acceso.",
  ],
  "Crie uma senha para entrar com o email desta conta.": [
    "Create a password to sign in with this account’s email.",
    "Crea una contraseña para entrar con el correo de esta cuenta.",
  ],
  "Informe a senha atual e a nova senha.": [
    "Enter your current password and the new password.",
    "Introduce la contraseña actual y la nueva.",
  ],
  "Verifique os campos.": ["Check the fields.", "Revisa los campos."],
  "Esqueci minha senha": ["Forgot password", "Olvidé mi contraseña"],
  "Enviaremos um código de 6 dígitos para o seu email.": [
    "We’ll send a 6-digit code to your email.",
    "Enviaremos un código de 6 dígitos a tu correo.",
  ],
  "Código de 6 dígitos": ["6-digit code", "Código de 6 dígitos"],
  "Nova senha (mín. 8)": ["New password (min. 8)", "Nueva contraseña (mín. 8)"],
  "Confirmar nova senha": ["Confirm new password", "Confirmar nueva contraseña"],
  "Enviar código": ["Send code", "Enviar código"],
  "Redefinir senha": ["Reset password", "Restablecer contraseña"],
  "Reenviar código": ["Resend code", "Reenviar código"],
  "Reenviar em %d s": ["Resend in %d s", "Reenviar en %d s"],
  "Enviando código…": ["Sending code…", "Enviando código…"],
  "Se existir uma conta, enviamos um código.": [
    "If an account exists, we sent a code.",
    "Si existe una cuenta, enviamos un código.",
  ],
  "Redefinindo senha…": ["Resetting password…", "Restableciendo contraseña…"],
  "Informe o código de 6 dígitos.": [
    "Enter the 6-digit code.",
    "Introduce el código de 6 dígitos.",
  ],
  "Código incorreto ou expirado.": [
    "Incorrect or expired code.",
    "Código incorrecto o caducado.",
  ],
  "Muitas tentativas com este código. Peça um novo.": [
    "Too many attempts with this code. Request a new one.",
    "Demasiados intentos con este código. Pide uno nuevo.",
  ],
  "Não foi possível enviar o código. Verifique a conexão.": [
    "Couldn’t send the code. Check your connection.",
    "No se pudo enviar el código. Comprueba la conexión.",
  ],
  "Não foi possível redefinir a senha. Verifique a conexão.": [
    "Couldn’t reset the password. Check your connection.",
    "No se pudo restablecer la contraseña. Comprueba la conexión.",
  ],
  "Não foi possível redefinir a senha.": [
    "Couldn’t reset the password.",
    "No se pudo restablecer la contraseña.",
  ],
  "Continuar com Apple": ["Continue with Apple", "Continuar con Apple"],
  Nome: ["Name", "Nombre"],
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
  "Entre no grupo «%@» no Katecheo": [
    "Join the “%@” group on Katecheo",
    "Únete al grupo «%@» en Katecheo",
  ],
  "Tentar de novo": ["Try again", "Intentar de nuevo"],
  "Puxe para atualizar quando a rede voltar.": [
    "Pull to refresh when you’re back online.",
    "Desliza para actualizar cuando vuelva la red.",
  ],
  // First-launch onboarding
  Pular: ["Skip", "Omitir"],
  Começar: ["Get started", "Empezar"],
  "Seu estudo bíblico, organizado": [
    "Your Bible study, organized",
    "Tu estudio bíblico, organizado",
  ],
  "Notas com referências": ["Notes with references", "Notas con referencias"],
  "Anote sermões e estudos e marque referências bíblicas que abrem no seu app de Bíblia.": [
    "Write sermon and study notes and mark Bible references that open in your own Bible app.",
    "Escribe notas de sermones y estudios y marca referencias bíblicas que se abren en tu app de Biblia.",
  ],
  "Temas e leitura": ["Themes and reading", "Temas y lectura"],
  "Organize por temas e acompanhe planos de leitura.": [
    "Organize by themes and follow reading plans.",
    "Organiza por temas y sigue planes de lectura.",
  ],
  "Grupos e amigos": ["Groups and friends", "Grupos y amigos"],
  "Compartilhe notas com amigos e grupos da igreja.": [
    "Share notes with friends and church groups.",
    "Comparte notas con amigos y grupos de la iglesia.",
  ],
  "Ver introdução": ["View intro", "Ver introducción"],
  "Ver de novo as telas iniciais": [
    "See the intro screens again",
    "Ver de nuevo las pantallas iniciales",
  ],
  "Boas-vindas ao Katecheo": ["Welcome to Katecheo", "Bienvenido a Katecheo"],
  "Pula a introdução e continua": [
    "Skips the intro and continues",
    "Omite la introducción y continúa",
  ],
  "Páginas da introdução": ["Intro pages", "Páginas de la introducción"],
  "Página %lld de %lld": ["Page %lld of %lld", "Página %lld de %lld"],

  // Post-sign-in settings guide
  "Passo %lld de %lld": ["Step %lld of %lld", "Paso %lld de %lld"],
  "Usa os padrões e continua": [
    "Uses the defaults and continues",
    "Usa los valores predeterminados y continúa",
  ],
  Continuar: ["Continue", "Continuar"],
  Concluir: ["Done", "Listo"],
  "Agora não": ["Not now", "Ahora no"],
  "Ativar notificações": ["Enable notifications", "Activar notificaciones"],
  "Escolha onde abrir as referências. Você pode mudar depois em Perfil.": [
    "Choose where to open references. You can change this later in Profile.",
    "Elige dónde abrir las referencias. Puedes cambiarlo después en Perfil.",
  ],
  "Usamos esta tradução nos links da Bíblia. Pode alterar a qualquer momento.": [
    "We use this translation for Bible links. You can change it anytime.",
    "Usamos esta traducción en los enlaces de la Biblia. Puedes cambiarla en cualquier momento.",
  ],
  "Avisos de planos de leitura, amigos, compartilhamentos e grupos. Você controla isso em Perfil.": [
    "Alerts for reading plans, friends, shares, and groups. You control this in Profile.",
    "Avisos de planes de lectura, amigos, compartidos y grupos. Lo controlas en Perfil.",
  ],
  "Não foi possível gerar o link agora. Tente de novo.": [
    "Couldn’t generate the link right now. Try again.",
    "No se pudo generar el enlace ahora. Inténtalo de nuevo.",
  ],
  "Link pronto": ["Link ready", "Enlace listo"],
  "Conclui a configuração": ["Finishes setup", "Termina la configuración"],

  // Notification Center — delete / clear all
  "Limpar tudo": ["Clear all", "Borrar todo"],
  "Limpar todos os avisos?": ["Clear all alerts?", "¿Borrar todos los avisos?"],
  "Isso remove os avisos da lista. Pedidos de amizade continuam em Amigos.": [
    "This removes alerts from the list. Friend requests stay in Friends.",
    "Esto elimina los avisos de la lista. Las solicitudes de amistad siguen en Amigos.",
  ],

  // Friends → public profile
  "Perfil indisponível": ["Profile unavailable", "Perfil no disponible"],
  "Não é possível ver este perfil.": [
    "This profile can’t be viewed.",
    "No es posible ver este perfil.",
  ],

};

/** Keys owned by the MANUAL table (safe to add into an existing hand catalog). */
const manualKeys = new Set(Object.keys(MANUAL));

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
  "KCDesign.swift",
  "AppDelegate.swift",
  "SceneDelegate.swift",
]);

const NEVER_WRAP = new Set([
  "init(coder:) has not been implemented",
  "Default Configuration",
  "spin",
  "transform.rotation.z",
  "KCNoteRowCell",
  "KCGroupRowCell",
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
  "Katecheo-dados.json",
  "https://katecheo.app/about",
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

function entryFromTranslation(key, tr) {
  return {
    extractionState: "manual",
    localizations: {
      "pt-BR": unit(key),
      en: unit(tr.en),
      es: unit(tr.es),
    },
  };
}

/**
 * Merge translations into an existing catalog.
 * Existing keys are preserved byte-for-byte (never deleted, never overwritten),
 * and their relative order is kept. New keys are appended (sorted) at the end.
 * When a catalog already exists, only missing MANUAL keys are added — we do not
 * bulk-import every `i18n.ts` phrase onto a hand-maintained file.
 * A missing catalog (greenfield) still builds from i18n + MANUAL (sorted).
 */
function mergeCatalog(existingCatalog, extraKeys = []) {
  const prior =
    existingCatalog && typeof existingCatalog === "object" && existingCatalog.strings
      ? existingCatalog.strings
      : {};
  const beforeKeys = Object.keys(prior);
  const beforeCount = beforeKeys.length;
  const strings = {};
  for (const key of beforeKeys) {
    strings[key] = prior[key];
  }
  let added = 0;
  const candidateKeys =
    beforeCount > 0
      ? [...manualKeys, ...extraKeys]
      : [...translations.keys(), ...extraKeys];
  const toAdd = [];
  for (const key of candidateKeys) {
    if (Object.prototype.hasOwnProperty.call(strings, key)) continue;
    const tr = translations.get(key);
    if (!tr?.en || !tr?.es) continue;
    toAdd.push(key);
  }
  for (const key of [...new Set(toAdd)].sort((a, b) => a.localeCompare(b, "pt-BR"))) {
    strings[key] = entryFromTranslation(key, translations.get(key));
    added += 1;
  }
  const afterKeys = Object.keys(strings);
  const afterCount = afterKeys.length;
  if (afterCount < beforeCount) {
    throw new Error(
      `generate-ios-l10n refused to shrink Localizable.xcstrings (${beforeCount} → ${afterCount})`,
    );
  }
  for (const key of beforeKeys) {
    if (!Object.prototype.hasOwnProperty.call(strings, key)) {
      throw new Error(`generate-ios-l10n refused to drop existing key: ${JSON.stringify(key)}`);
    }
    if (strings[key] !== prior[key] && JSON.stringify(strings[key]) !== JSON.stringify(prior[key])) {
      throw new Error(`generate-ios-l10n refused to overwrite existing key: ${JSON.stringify(key)}`);
    }
  }
  // Existing relative order must stay identical.
  if (beforeKeys.length && afterKeys.slice(0, beforeKeys.length).join("\0") !== beforeKeys.join("\0")) {
    throw new Error("generate-ios-l10n refused to reorder existing Localizable keys");
  }
  return {
    catalog: {
      sourceLanguage: "pt-BR",
      strings,
      version: existingCatalog?.version || "1.0",
    },
    beforeCount,
    afterCount,
    added,
  };
}

function writeJson(filePath, obj) {
  fs.writeFileSync(filePath, `${JSON.stringify(obj, null, 2)}\n`);
}

const catalogPath = path.join(appDir, "Localizable.xcstrings");
const infoPlistCatalogPath = path.join(appDir, "InfoPlist.xcstrings");

let existingCatalog = null;
if (fs.existsSync(catalogPath)) {
  existingCatalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
}
const merged = mergeCatalog(existingCatalog);
writeJson(catalogPath, merged.catalog);

// InfoPlist is tiny and owned by this script; only ensure Katecheo display names.
const existingInfo = fs.existsSync(infoPlistCatalogPath)
  ? JSON.parse(fs.readFileSync(infoPlistCatalogPath, "utf8"))
  : { sourceLanguage: "pt-BR", strings: {}, version: "1.0" };
const infoStrings = { ...(existingInfo.strings || {}) };
for (const key of ["CFBundleDisplayName", "CFBundleName"]) {
  if (!infoStrings[key]) {
    infoStrings[key] = {
      extractionState: "manual",
      localizations: {
        "pt-BR": unit("Katecheo"),
        en: unit("Katecheo"),
        es: unit("Katecheo"),
      },
    };
  }
}
writeJson(infoPlistCatalogPath, {
  sourceLanguage: "pt-BR",
  strings: infoStrings,
  version: existingInfo.version || "1.0",
});

console.log(
  `Merged ${path.relative(root, catalogPath)}: ${merged.beforeCount} existing + ${merged.added} new = ${merged.afterCount} keys (never deletes)`,
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
