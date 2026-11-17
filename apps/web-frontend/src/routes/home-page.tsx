export function HomePage() {
  return (
    <section className="flex flex-col items-start gap-2 rounded-xl border border-dashed border-border p-8">
      <h2 className="font-heading text-lg font-medium">Tu recetario está vacío</h2>
      <p className="text-sm text-muted-foreground">
        Todavía no hay recetas que mostrar. Aparecerán aquí en cuanto los servicios estén
        conectados.
      </p>
    </section>
  )
}
