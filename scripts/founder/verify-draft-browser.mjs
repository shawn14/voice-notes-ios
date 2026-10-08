// Run from cua_repl with its documented tab and viewport handles.
// This checks the actual rendered agent output; it cannot turn static output into a browser pass.
import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
export async function verifyDraftBrowser(tab, viewport, receiptDir) {
  await mkdir(receiptDir, { recursive: true })
  const views = []
  try {
    for (const size of [{width:1440,height:900},{width:390,height:844}]) {
      await viewport.set(size)
      await tab.playwright.domSnapshot()
      const state = await tab.playwright.evaluate(() => {
        const heading = document.querySelector('#surface-heading').getBoundingClientRect()
        const footer = document.querySelector('.capture-bar').getBoundingClientRect()
        return {width:innerWidth,height:innerHeight,overflow:document.documentElement.scrollWidth>innerWidth,
          draft:/draft prototype/i.test(document.body.innerText),unavailable:/unavailable in draft/i.test(document.body.innerText),
          buttons:Array.from(document.querySelectorAll('button')).map(b=>({text:b.textContent.trim(),disabled:b.disabled})),
          workingTop:heading.top,workingBottom:heading.bottom,footerTop:footer.top,
          anchors:Array.from(document.querySelectorAll('a[href]')).map(a=>({href:a.getAttribute('href'),exists:!!document.querySelector(a.getAttribute('href'))}))}
      })
      assert.equal(state.width,size.width)
      assert(!state.overflow && state.draft && state.unavailable)
      assert(state.buttons.length && state.buttons.every(button=>button.disabled),'Unavailable capture must not silently do nothing')
      assert(state.anchors.every(anchor=>anchor.exists),'Every local link must resolve')
      assert(state.workingTop>=0 && state.workingBottom<state.footerTop)
      if (size.width>500) assert(state.workingTop<300,'Desktop working surface must not sit below a blank hero')
      views.push(state)
      await writeFile(join(receiptDir,size.width>500?'desktop.jpg':'mobile.jpg'),await tab.getScreenshot({emit:false}))
    }
    await tab.playwright.getByRole('link',{name:'Browse knowledge',exact:true}).click()
    await tab.playwright.domSnapshot()
    const navigation={url:await tab.url(),headingVisible:await tab.playwright.getByRole('heading',{name:'Knowledge Layer',exact:true}).isVisible()}
    assert(navigation.url.endsWith('#knowledge') && navigation.headingVisible)
    const errors=await tab.dev.logs({levels:['error'],limit:30})
    assert.equal(errors.length,0,'Actual browser errors fail the generated artifact')
    const receipt={passed:true,views,navigation,errors,scope:'local draft browser proof; capture intentionally unavailable, no publication'}
    await writeFile(join(receiptDir,'browser-proof.json'),JSON.stringify(receipt,null,2))
    return receipt
  } finally { await viewport.reset() }
}
