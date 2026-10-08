// Exporta los glifos de la barra del Finder tal como los dibuja macOS, para
// que el tema Constanza los use en Linux. Se corre EN la Mac (Catalina):
//
//     swift exportar-glifos.swift
//
// Escribe en /Users/Shared/glifos-finder/: pdf/ (vector) y png/ a 1x y 2x,
// más encontrados.txt y no-encontrados.txt. No modifica nada más.
// Lo que exporta es de Apple: es para uso local y no va a ningún repo.
import AppKit

let salida = URL(fileURLWithPath: "/Users/Shared/glifos-finder")
let fm = FileManager.default
for sub in ["pdf", "png"] {
    try? fm.createDirectory(at: salida.appendingPathComponent(sub), withIntermediateDirectories: true)
}

// Nombres de sistema de AppKit que usa la barra del Finder (y vecinos útiles).
let nombresSistema = [
    "NSGoLeftTemplate", "NSGoRightTemplate", "NSGoBackTemplate", "NSGoForwardTemplate",
    "NSIconViewTemplate", "NSListViewTemplate", "NSColumnViewTemplate", "NSFlowViewTemplate",
    "NSActionTemplate", "NSShareTemplate", "NSSmartBadgeTemplate", "NSPathTemplate",
    "NSQuickLookTemplate", "NSRevealFreestandingTemplate", "NSFollowLinkFreestandingTemplate",
    "NSAddTemplate", "NSRemoveTemplate", "NSRefreshTemplate", "NSRefreshFreestandingTemplate",
    "NSStopProgressTemplate", "NSStopProgressFreestandingTemplate", "NSInvalidDataFreestandingTemplate",
    "NSLockLockedTemplate", "NSLockUnlockedTemplate", "NSEnterFullScreenTemplate", "NSExitFullScreenTemplate",
    "NSMenuOnStateTemplate", "NSMenuMixedStateTemplate", "NSTouchBarSearchTemplate", "NSTouchBarTagIconTemplate",
    "NSTouchBarShareTemplate", "NSTouchBarGoBackTemplate", "NSTouchBarGoForwardTemplate",
    "NSTouchBarIconViewTemplate", "NSTouchBarListViewTemplate", "NSTouchBarColumnViewTemplate",
    "NSTouchBarGetInfoTemplate", "NSTouchBarDeleteTemplate", "NSTouchBarNewFolderTemplate",
    "NSTouchBarFolderTemplate", "NSTouchBarSidebarTemplate", "NSTouchBarQuickLookTemplate",
    "NSTouchBarRecordStartTemplate", "NSTouchBarComposeTemplate", "NSTouchBarSearchTemplate",
    "NSNavEjectButton.normal", "NSToolbarShowColors", "NSToolbarShowFonts",
    "NSFolder", "NSFolderBurnable", "NSFolderSmart", "NSNetwork", "NSComputer",
    "NSBookmarksTemplate", "NSSlideshowTemplate", "NSHomeTemplate",
]

// Los propios del Finder (Finder.app/Contents/Resources/Assets.car).
let finder = Bundle(path: "/System/Library/CoreServices/Finder.app")
let nombresFinder = [
    "GalleryViewToolBarTemplate", "GalleryViewTouchBarTemplate", "ToolbarBurnTemplate",
    "ToolbarConnectTemplate", "i_info", "kit_share_airdrop", "kit_share_iCloud",
    "kit_tabBar_addTab", "QuickActionMore", "finder_window_new", "finder_connect",
    "EjectMedia-dark", "HeaderArrowDown", "HeaderArrowUp", "noWrite",
]

var encontrados: [String] = [], faltan: [String] = []

func guardar(_ img: NSImage, _ nombre: String) {
    let tam = img.size.width > 0 ? img.size : NSSize(width: 16, height: 16)
    // PDF vectorial: se dibuja la imagen en un contexto PDF del mismo tamaño.
    let datos = NSMutableData()
    var caja = CGRect(origin: .zero, size: tam)
    if let consumidor = CGDataConsumer(data: datos as CFMutableData),
       let ctx = CGContext(consumer: consumidor, mediaBox: &caja, nil) {
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: caja)
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage(); ctx.closePDF()
        datos.write(to: salida.appendingPathComponent("pdf/\(nombre).pdf"), atomically: true)
    }
    // PNG a 1x y 2x, con transparencia.
    for escala in [1, 2] {
        let w = Int(tam.width) * escala, h = Int(tam.height) * escala
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        rep.size = tam
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: tam))
        NSGraphicsContext.restoreGraphicsState()
        let sufijo = escala == 1 ? "" : "@2x"
        try? rep.representation(using: .png, properties: [:])?
            .write(to: salida.appendingPathComponent("png/\(nombre)\(sufijo).png"))
    }
    encontrados.append("\(nombre)\t\(Int(tam.width))x\(Int(tam.height))\t\(img.isTemplate ? "template" : "color")")
}

for n in nombresSistema {
    if let img = NSImage(named: NSImage.Name(n)) { guardar(img, n) } else { faltan.append(n) }
}
for n in nombresFinder {
    if let img = finder?.image(forResource: NSImage.Name(n)) { guardar(img, "Finder-" + n) } else { faltan.append("Finder-" + n) }
}
// La lupa del campo de búsqueda: la trae la celda del NSSearchField.
if let lupa = NSSearchFieldCell().searchButtonCell?.image { guardar(lupa, "NSSearchField-lupa") } else { faltan.append("NSSearchField-lupa") }
if let x = NSSearchFieldCell().cancelButtonCell?.image { guardar(x, "NSSearchField-borrar") } else { faltan.append("NSSearchField-borrar") }

try? encontrados.joined(separator: "\n").write(to: salida.appendingPathComponent("encontrados.txt"), atomically: true, encoding: .utf8)
try? faltan.joined(separator: "\n").write(to: salida.appendingPathComponent("no-encontrados.txt"), atomically: true, encoding: .utf8)
print("Encontrados: \(encontrados.count) · no encontrados: \(faltan.count)")
print("Listo en \(salida.path). Ya puedes volver a Linux.")
