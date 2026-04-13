const app = Vue.createApp({
    //data, functions
    //  template: '<h2>I am the template </h2>'
    data() {
        return {
        showBooks: true,
        title: "The Desires of Ages",
        author: "Ellen G White",
        year: 1907,
        age: 32,
        publisher: "EGW-Estate.press",
        x: 0,
        y: 0
        }

    },
    // Also you can upadte the property inside this component
    methods: {
        changeTitle () {
            this.title = "The SDA Church Manual"
        },
        toggleShowBooks (){
            this.showBooks = !this.showBooks
        },
        handleEvent() {
            console.log("Event on mouse hover")
        },
        handleEventleave(){
            console.log("you Leave over the content")
        },
        handleEventDouble() {
            console.log("you double click the Content")
        },
        handleMouseMove(e) {
            this.x = e.offsetx
            this.y = e.offsety
        }


    }
}) 


app.mount("#app")